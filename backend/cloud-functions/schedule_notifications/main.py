import functions_framework
import json
import uuid
import firebase_admin
from firebase_admin import credentials, messaging, firestore
from datetime import datetime, timedelta
from google.cloud import scheduler_v1
import os

# Initialize Firebase Admin SDK (for FCM)
# In production, use environment variable or Secret Manager for credentials path
cred = credentials.ApplicationDefault()
try:
    firebase_admin.initialize_app(cred)
except ValueError:
    # Already initialized
    pass

# Initialize Firestore DB
db = firestore.Client()

# Initialize Cloud Scheduler client
scheduler_client = scheduler_v1.CloudSchedulerClient()
project_id = os.environ.get('PROJECT_ID', 'pep-pro')
location_id = 'us-central1'
parent = f"projects/{project_id}/locations/{location_id}"

@functions_framework.http
def schedule_notifications(request):
    """
    Cloud Function to schedule exercise notifications for a patient.
    
    Request format:
    {
        "patient_id": "uuid-of-patient",
        "schedule": {
            "frequency": "daily", 
            "time": "09:00", 
            "days": ["monday", "wednesday", "friday"]  // for weekly schedules
        },
        "fcm_token": "firebase-cloud-messaging-token"
    }
    """
    # Enable CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        request_json = request.get_json(silent=True)
        
        if not request_json or 'patient_id' not in request_json:
            return (json.dumps({'error': 'Invalid request - missing patient_id'}), 400, headers)
        
        patient_id = request_json['patient_id']
        schedule = request_json.get('schedule', {'frequency': 'daily', 'time': '09:00'})
        fcm_token = request_json.get('fcm_token')
        
        # Validate FCM token
        if not fcm_token:
            return (json.dumps({'error': 'Missing FCM token'}), 400, headers)
        
        # Save FCM token to patient record
        db.collection('patients').document(patient_id).update({
            'fcm_token': fcm_token,
            'updated_at': datetime.now()
        })
        
        # Get patient exercises
        patient_exercises = db.collection('patient_exercises').where('patient_id', '==', patient_id).get()
        
        if len(patient_exercises) == 0:
            return (json.dumps({'error': 'No exercises found for patient'}), 404, headers)
        
        # Create a Cloud Scheduler job for notifications
        frequency = schedule.get('frequency', 'daily')
        time = schedule.get('time', '09:00')
        days = schedule.get('days', [])
        
        # Create scheduler job
        job = create_scheduler_job(patient_id, frequency, time, days)
        
        # Schedule immediate notification as well
        send_exercise_notification(patient_id, fcm_token)
        
        # Return success response
        response = {
            'status': 'success',
            'scheduler_job': job,
            'message': 'Notifications scheduled successfully'
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': f'Error scheduling notifications: {str(e)}'}), 500, headers)


def create_scheduler_job(patient_id, frequency, time, days):
    """
    Create a Cloud Scheduler job to trigger notifications
    """
    # Delete any existing jobs for this patient
    try:
        existing_jobs = scheduler_client.list_jobs(request={"parent": parent})
        for job in existing_jobs:
            if f"patient-{patient_id}" in job.name:
                scheduler_client.delete_job(request={"name": job.name})
    except Exception as e:
        print(f"Error cleaning up existing jobs: {str(e)}")
    
    # Create a new job
    hour, minute = time.split(':')
    
    # Set up schedule based on frequency
    if frequency == 'daily':
        schedule = f"{minute} {hour} * * *"  # Every day at specified time
    elif frequency == 'weekly':
        if not days or len(days) == 0:
            days = ['monday']  # Default to Monday
        
        # Convert days to cron format (0=Sunday, 1=Monday, etc.)
        day_map = {
            'sunday': 0, 'monday': 1, 'tuesday': 2, 'wednesday': 3,
            'thursday': 4, 'friday': 5, 'saturday': 6
        }
        day_numbers = [str(day_map.get(day.lower(), 1)) for day in days]
        day_spec = ','.join(day_numbers)
        
        schedule = f"{minute} {hour} * * {day_spec}"  # Weekly on specified days
    else:
        # Default to daily
        schedule = f"{minute} {hour} * * *"
    
    # Create HTTP target for the Cloud Function that sends notifications
    target_function_url = f"https://{location_id}-{project_id}.cloudfunctions.net/send_notification"
    
    job_name = f"{parent}/jobs/patient-{patient_id}-notifications"
    
    job = {
        "name": job_name,
        "description": f"Exercise notification schedule for patient {patient_id}",
        "schedule": schedule,
        "time_zone": "America/Los_Angeles",  # This should be configurable
        "http_target": {
            "uri": target_function_url,
            "http_method": scheduler_v1.HttpMethod.POST,
            "body": json.dumps({
                "patient_id": patient_id
            }).encode(),
            "headers": {
                "Content-Type": "application/json"
            }
        }
    }
    
    # Create or update the job
    try:
        response = scheduler_client.create_job(
            request={"parent": parent, "job": job}
        )
        return {
            "name": response.name,
            "schedule": response.schedule,
            "time_zone": response.time_zone,
            "state": str(response.state)
        }
    except Exception as e:
        # If job already exists, update it
        try:
            response = scheduler_client.update_job(
                request={"job": job}
            )
            return {
                "name": response.name,
                "schedule": response.schedule,
                "time_zone": response.time_zone,
                "state": str(response.state)
            }
        except Exception as update_error:
            raise Exception(f"Failed to create or update scheduler job: {str(update_error)}")


@functions_framework.http
def send_notification(request):
    """
    Cloud Function to send a notification to a patient.
    This is triggered by Cloud Scheduler.
    
    Request format:
    {
        "patient_id": "uuid-of-patient"
    }
    """
    try:
        request_json = request.get_json(silent=True)
        
        if not request_json or 'patient_id' not in request_json:
            return (json.dumps({'error': 'Invalid request - missing patient_id'}), 400)
        
        patient_id = request_json['patient_id']
        
        # Get patient FCM token
        patient_doc = db.collection('patients').document(patient_id).get()
        
        if not patient_doc.exists:
            return (json.dumps({'error': 'Patient not found'}), 404)
        
        patient_data = patient_doc.to_dict()
        fcm_token = patient_data.get('fcm_token')
        
        if not fcm_token:
            return (json.dumps({'error': 'Patient has no FCM token'}), 400)
        
        # Send the notification
        result = send_exercise_notification(patient_id, fcm_token)
        
        # Return success response
        return (json.dumps({
            'status': 'success',
            'result': result,
            'message': 'Notification sent successfully'
        }), 200)
        
    except Exception as e:
        return (json.dumps({'error': f'Error sending notification: {str(e)}'}), 500)


def send_exercise_notification(patient_id, fcm_token):
    """
    Send an exercise reminder notification to a patient's device via FCM
    """
    # Get patient details
    patient_doc = db.collection('patients').document(patient_id).get()
    patient_data = patient_doc.to_dict()
    patient_name = patient_data.get('name', 'Patient')
    
    # Get patient exercises
    patient_exercises = db.collection('patient_exercises').where('patient_id', '==', patient_id).get()
    exercise_ids = [doc.to_dict().get('exercise_id') for doc in patient_exercises]
    
    # Get exercise details
    exercise_names = []
    for ex_id in exercise_ids:
        ex_doc = db.collection('exercises').document(ex_id).get()
        if ex_doc.exists:
            ex_data = ex_doc.to_dict()
            exercise_names.append(ex_data.get('name'))
    
    # Create notification content
    title = "Time for your PT exercises!"
    
    if len(exercise_names) > 0:
        body = f"Hi {patient_name}! Don't forget to complete your exercises today: {', '.join(exercise_names[:3])}"
        if len(exercise_names) > 3:
            body += f" and {len(exercise_names) - 3} more."
    else:
        body = f"Hi {patient_name}! Don't forget to complete your exercises today."
    
    # Save notification to database
    notification_id = str(uuid.uuid4())
    notification = {
        'id': notification_id,
        'patient_id': patient_id,
        'title': title,
        'body': body,
        'scheduled_for': datetime.now(),
        'exercise_ids': exercise_ids,
        'status': 'sending',
        'created_at': datetime.now()
    }
    
    db.collection('notifications').document(notification_id).set(notification)
    
    # Create message
    message = messaging.Message(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data={
            'type': 'exercise_reminder',
            'patient_id': patient_id,
            'notification_id': notification_id,
        },
        token=fcm_token,
        android=messaging.AndroidConfig(
            priority='high',
            notification=messaging.AndroidNotification(
                icon='notification_icon',
                color='#4285F4',
                channel_id='exercise_reminders'
            ),
        ),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(
                        title=title,
                        body=body,
                    ),
                    badge=1,
                    sound='default',
                    category='EXERCISE_REMINDER',
                ),
            ),
        ),
    )
    
    # Send message
    try:
        response = messaging.send(message)
        
        # Update notification status
        db.collection('notifications').document(notification_id).update({
            'status': 'sent',
            'fcm_response': response,
            'updated_at': datetime.now()
        })
        
        return {
            'success': True,
            'message_id': response,
            'notification_id': notification_id
        }
    except Exception as e:
        # Update notification status
        db.collection('notifications').document(notification_id).update({
            'status': 'failed',
            'error': str(e),
            'updated_at': datetime.now()
        })
        
        raise Exception(f"Failed to send notification: {str(e)}")