import functions_framework
import json
import uuid
from google.cloud import firestore, storage
from datetime import datetime
import base64

# Initialize Firestore DB
db = firestore.Client()
# Initialize Cloud Storage
storage_client = storage.Client()
bucket_name = "duoligo-pt-app-videos"  # This bucket should be created in GCP

# Custom JSON encoder to handle datetime objects
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        # Handle Firestore's DatetimeWithNanoseconds
        if hasattr(obj, 'seconds') and hasattr(obj, 'nanos'):
            return datetime.fromtimestamp(obj.seconds + obj.nanos/1e9).isoformat()
        return super(DateTimeEncoder, self).default(obj)
    
@functions_framework.http
def modify_exercise(request):
    """
    Cloud Function for physical therapists to modify exercises.
    
    Request format:
    {
        "pt_id": "uuid-of-pt",
        "patient_id": "uuid-of-patient",
        "patient_exercise_id": "uuid-of-patient-exercise",
        "modifications": {
            "frequency": "daily",
            "sets": 3,
            "repetitions": 10,
            "notes": "Start with lower intensity"
        },
        "custom_video": {
            "base64_data": "base64-encoded-video-data",
            "content_type": "video/mp4",
            "filename": "exercise-video.mp4"
        }
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
        
        if not request_json or 'patient_exercise_id' not in request_json:
            return (json.dumps({'error': 'Invalid request - missing patient_exercise_id'}, cls=DateTimeEncoder), 400, headers)
        
        pt_id = request_json.get('pt_id')
        patient_id = request_json.get('patient_id')
        patient_exercise_id = request_json.get('patient_exercise_id')
        modifications = request_json.get('modifications', {})
        custom_video = request_json.get('custom_video')
        
        # Get the patient exercise document
        patient_exercise_ref = db.collection('patient_exercises').document(patient_exercise_id)
        patient_exercise_doc = patient_exercise_ref.get()
        
        if not patient_exercise_doc.exists:
            return (json.dumps({'error': 'Patient exercise not found'}, cls=DateTimeEncoder), 404, headers)
        
        # Get the exercise document
        patient_exercise_data = patient_exercise_doc.to_dict()
        exercise_id = patient_exercise_data.get('exercise_id')
        exercise_ref = db.collection('exercises').document(exercise_id)
        exercise_doc = exercise_ref.get()
        
        if not exercise_doc.exists:
            return (json.dumps({'error': 'Exercise not found'}, cls=DateTimeEncoder), 404, headers)
        
        exercise_data = exercise_doc.to_dict()
        
        # Update patient exercise with modifications
        update_data = {
            'pt_modified': True,
            'pt_id': pt_id,
            'updated_at': datetime.now()
        }
        
        if 'frequency' in modifications:
            update_data['frequency'] = modifications['frequency']
        
        if 'sets' in modifications:
            update_data['sets'] = modifications['sets']
            
        if 'repetitions' in modifications:
            update_data['repetitions'] = modifications['repetitions']
            
        if 'notes' in modifications:
            update_data['notes'] = modifications['notes']
        
        # Update the patient exercise document
        patient_exercise_ref.update(update_data)
        
        # If a custom video was provided, upload it to Cloud Storage
        video_url = None
        if custom_video and 'base64_data' in custom_video:
            try:
                # Get video data
                video_data = base64.b64decode(custom_video['base64_data'])
                content_type = custom_video.get('content_type', 'video/mp4')
                filename = custom_video.get('filename', f'{exercise_id}-{patient_id}.mp4')
                
                # Create a unique filename to avoid collisions
                blob_name = f"exercise-videos/{patient_id}/{exercise_id}/{uuid.uuid4()}-{filename}"
                
                # Get the bucket
                bucket = storage_client.bucket(bucket_name)
                # Create a new blob
                blob = bucket.blob(blob_name)
                # Upload the video
                blob.upload_from_string(video_data, content_type=content_type)
                
                # Make the blob publicly readable
                blob.make_public()
                
                # Get the public URL
                video_url = blob.public_url
                
                # Update the exercise with the custom video URL
                # Note: This creates a custom version just for this patient
                new_exercise_id = str(uuid.uuid4())
                new_exercise_data = exercise_data.copy()
                
                new_exercise_data.update({
                    'id': new_exercise_id,
                    'video_url': video_url,
                    'is_template': False,
                    'source': 'pt-created',
                    'original_exercise_id': exercise_id,
                    'created_at': datetime.now(),
                    'created_by': pt_id
                })
                
                # Save the new exercise
                db.collection('exercises').document(new_exercise_id).set(new_exercise_data)
                
                # Update the patient-exercise link to point to the new exercise
                patient_exercise_ref.update({
                    'exercise_id': new_exercise_id
                })
                
            except Exception as e:
                return (json.dumps({'error': f'Error uploading video: {str(e)}'}, cls=DateTimeEncoder), 500, headers)
        
        # Get the updated exercise data to return
        updated_patient_exercise = patient_exercise_ref.get().to_dict()
        updated_exercise_ref = db.collection('exercises').document(updated_patient_exercise['exercise_id'])
        updated_exercise = updated_exercise_ref.get().to_dict()
        
        # Return success response
        response = {
            'status': 'success',
            'patient_exercise': updated_patient_exercise,
            'exercise': updated_exercise,
            'message': 'Exercise successfully modified'
        }
        
        return (json.dumps(response, cls=DateTimeEncoder), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': f'Error modifying exercise: {str(e)}'}, cls=DateTimeEncoder), 500, headers)