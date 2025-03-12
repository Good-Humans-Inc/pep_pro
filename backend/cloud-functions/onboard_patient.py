import uuid
import json
import functions_framework
from google.cloud import firestore
from datetime import datetime
import re

@functions_framework.http
def onboard_patient(request):
    """
    Cloud Function to handle patient onboarding.
    Receives data from the iOS app, parses it, and stores in Firestore.
    
    Request format:
    {
        "voice_input": "My name is John, I'm 45 years old. My knee hurts when I climb stairs, 
                        the pain is about 7 out of 10. I'd like to exercise daily."
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
        
        if not request_json or 'voice_input' not in request_json:
            return (json.dumps({'error': 'Invalid request - missing voice input'}), 400, headers)
        
        # Get the voice input
        voice_input = request_json['voice_input']
        
        # Parse the voice input
        patient_data = parse_patient_data(voice_input)
        
        # Create a new patient record in Firestore
        db = firestore.Client()
        
        # Generate a unique ID for the patient
        patient_id = str(uuid.uuid4())
        
        # Create patient document
        patient_doc = {
            'id': patient_id,
            'name': patient_data['name'],
            'age': patient_data['age'],
            'exercise_frequency': patient_data['exercise_frequency'],
            'created_at': datetime.now(),
            'updated_at': datetime.now()
        }
        
        # Save patient to Firestore
        db.collection('patients').document(patient_id).set(patient_doc)
        
        # Create pain point document
        if 'pain_description' in patient_data:
            pain_point_id = str(uuid.uuid4())
            pain_point = {
                'id': pain_point_id,
                'patient_id': patient_id,
                'description': patient_data['pain_description'],
                'severity': patient_data['pain_severity'],
                'created_at': datetime.now()
            }
            
            # Save pain point to Firestore
            db.collection('pain_points').document(pain_point_id).set(pain_point)
        
        # Return success response with patient ID
        response = {
            'status': 'success',
            'patient_id': patient_id,
            'message': 'Patient successfully onboarded'
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': f'Error processing request: {str(e)}'}), 500, headers)


def parse_patient_data(voice_input):
    """
    Parse the voice input to extract patient data using regex patterns
    """
    data = {}
    
    # Extract name
    name_match = re.search(r"(?:I'm|I am|My name is|name's|call me) ([A-Za-z]+)", voice_input)
    if name_match:
        data['name'] = name_match.group(1)
    else:
        data['name'] = "Unknown"
    
    # Extract age
    age_match = re.search(r"(\d+)(?:\s+|\-)?(?:years?|yrs?)(?:\s+|\-)?old", voice_input)
    if age_match:
        data['age'] = int(age_match.group(1))
    else:
        data['age'] = 0
    
    # Extract pain description
    pain_match = re.search(r"(?:my|the)?\s*(?:knee|pain|ache)(?:\s+|\-)?(?:is|feels|hurts)?\s*([^.]+)", voice_input, re.IGNORECASE)
    if pain_match:
        data['pain_description'] = pain_match.group(1).strip()
    
    # Extract pain severity (1-10 scale)
    severity_match = re.search(r"(?:pain|ache)(?:\s+|\-)?is\s*(?:about|around)?\s*(\d+)(?:\s+|\-)?(?:out of|\/)\s*10", voice_input, re.IGNORECASE)
    if severity_match:
        data['pain_severity'] = int(severity_match.group(1))
    else:
        data['pain_severity'] = 5  # Default to mid-scale if not specified
    
    # Extract exercise frequency
    if re.search(r"(?:daily|every\s*day)", voice_input, re.IGNORECASE):
        data['exercise_frequency'] = "daily"
    elif re.search(r"(?:twice|2(?:\s+|\-)?times)(?:\s+|\-)?(?:a|per)(?:\s+|\-)?(?:day|daily)", voice_input, re.IGNORECASE):
        data['exercise_frequency'] = "twice-daily"
    elif re.search(r"(?:weekly|once(?:\s+|\-)?a(?:\s+|\-)?week)", voice_input, re.IGNORECASE):
        data['exercise_frequency'] = "weekly"
    elif re.search(r"(?:twice|2(?:\s+|\-)?times)(?:\s+|\-)?(?:a|per)(?:\s+|\-)?week", voice_input, re.IGNORECASE):
        data['exercise_frequency'] = "twice-weekly"
    elif re.search(r"(?:3|three)(?:\s+|\-)?times(?:\s+|\-)?(?:a|per)(?:\s+|\-)?week", voice_input, re.IGNORECASE):
        data['exercise_frequency'] = "3x-weekly"
    else:
        data['exercise_frequency'] = "daily"  # Default if not specified
    
    return data