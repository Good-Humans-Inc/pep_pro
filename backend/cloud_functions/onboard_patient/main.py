import uuid
import json
import functions_framework
import os
import logging
from google.cloud import firestore
from datetime import datetime
import re

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Custom JSON encoder to handle datetime objects
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        # Handle Firestore's DatetimeWithNanoseconds
        if hasattr(obj, 'seconds') and hasattr(obj, 'nanos'):
            return datetime.fromtimestamp(obj.seconds + obj.nanos/1e9).isoformat()
        return super(DateTimeEncoder, self).default(obj)

# Initialize Firestore DB
db = firestore.Client()

# Valid frequency values - all lowercase for case-insensitive comparison
VALID_FREQUENCIES = [
    "Daily",
    "daily",
    "2 times a week",
    "3 times a week", 
    "4 times a week",
    "5 times a week",
    "6 times a week",
    "everyday",
    "every other day",
    "Everyday",
    "Every other day"
]

@functions_framework.http
def onboard_patient(request):
    """
    Cloud Function to handle patient onboarding with structured JSON only.
    
    Required fields:
    - name (str): Patient's name
    - age (int): Patient's age (5-100)
    - injury (str): Description of the injury or pain
    - pain_level (int): Pain severity (1-10)
    - frequency (str): Exercise frequency (see VALID_FREQUENCIES)
    - time_of_day (str): Preferred exercise time (HH:MM in 24hr format)
    - notification_time (str): Notification time (HH:MM in 24hr format)
    - goal (str): Patient's recovery goal
    
    Optional fields:
    - fcm_token (str): Firebase Cloud Messaging token for notifications
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
        
        if not request_json:
            logger.error("Invalid request - missing JSON data")
            return (json.dumps({'error': 'Invalid request - missing data'}, cls=DateTimeEncoder), 400, headers)
        
        # Log incoming request for debugging
        logger.info(f"Received request: {json.dumps(request_json)}")
        
        # Process structured JSON only
        return process_structured_onboarding(request_json, headers)
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return (json.dumps({'error': f'Error processing request: {str(e)}'}, cls=DateTimeEncoder), 500, headers)


def process_structured_onboarding(request_data, headers):
    """
    Process structured JSON input for patient onboarding with validation.
    
    Required fields:
    - name (str): Patient's name
    - age (int): Patient's age (5-100)
    - injury (str): Description of the injury or pain
    - pain_level (int): Pain severity (1-10)
    - frequency (str): Exercise frequency (see VALID_FREQUENCIES)
    - time_of_day (str): Preferred exercise time
    - notification_time (str): Notification time (HH:MM in 24hr format)
    - goal (str): Patient's recovery goal
    """
    try:
        # Extract fields
        name = request_data.get('name')
        age = request_data.get('age')
        injury = request_data.get('injury')
        pain_level = request_data.get('pain_level')
        frequency = request_data.get('frequency')
        time_of_day = request_data.get('time_of_day')
        notification_time = request_data.get('notification_time')
        goal = request_data.get('goal')
        fcm_token = request_data.get('fcm_token', '')
        
        # Check for missing required fields
        required_fields = ['name', 'age', 'injury', 'pain_level', 'frequency', 'time_of_day', 'notification_time', 'goal']
        missing_fields = [field for field in required_fields if field not in request_data]
        
        if missing_fields:
            error_msg = f"Missing required fields: {', '.join(missing_fields)}"
            logger.error(error_msg)
            return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
        
        # Validate age (5-100)
        try:
            age = int(age)
            if not (5 <= age <= 100):
                error_msg = f"Age must be between 5 and 100, got {age}"
                logger.error(error_msg)
                return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
        except (ValueError, TypeError):
            error_msg = f"Age must be an integer between 5 and 100, got {age}"
            logger.error(error_msg)
            return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
        
        # Validate pain level (1-10)
        try:
            pain_level = int(pain_level)
            if not (1 <= pain_level <= 10):
                error_msg = f"Pain level must be between 1 and 10, got {pain_level}"
                logger.error(error_msg)
                return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
        except (ValueError, TypeError):
            error_msg = f"Pain level must be an integer between 1 and 10, got {pain_level}"
            logger.error(error_msg)
            return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
        
        # Normalize and validate frequency (case-insensitive check)
        if frequency is None:
            frequency = ""
            
        # Convert to lowercase for case-insensitive validation
        frequency_lower = frequency.lower()
        
        if frequency_lower not in VALID_FREQUENCIES:
            # Log exact state for debugging
            logger.error(f"Invalid frequency: '{frequency_lower}' not in {VALID_FREQUENCIES}")
            valid_options = ", ".join(VALID_FREQUENCIES)
            error_msg = f"Invalid frequency value. Must be one of: {valid_options}"
            return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
        
        # Validate notification_time format (HH:MM, 24hr)
        if not re.match(r'^([01]\d|2[0-3]):([0-5]\d)$', notification_time):
            error_msg = f"Invalid notification time format. Must be HH:MM in 24-hour format, got {notification_time}"
            logger.error(error_msg)
            return (json.dumps({'error': error_msg}, cls=DateTimeEncoder), 400, headers)
            
        # Create patient ID
        patient_id = str(uuid.uuid4())
        created_at = datetime.now()

        # Create and store patient document
        patient_doc = {
            'id': patient_id,
            'name': name,
            'age': age,
            'pain_description': injury,
            'pain_severity': pain_level,
            'exercise_frequency': frequency_lower,  # Store the normalized version
            'preferred_time': time_of_day,
            'notification_time': notification_time,
            'goal': goal,
            'fcm_token': fcm_token,
            'created_at': created_at,
            'updated_at': created_at
        }

        # Save to Firestore
        db.collection('patients').document(patient_id).set(patient_doc)
        logger.info(f"Created patient with ID: {patient_id}")

        # Return success response
        return (json.dumps({
            'status': 'success',
            'message': 'Patient onboarded successfully',
            'patient_id': patient_id
        }, cls=DateTimeEncoder), 200, headers)

    except Exception as e:
        logger.error(f"Error in process_structured_onboarding: {str(e)}")
        return (json.dumps({'error': f'Failed to onboard patient: {str(e)}'}, cls=DateTimeEncoder), 500, headers)