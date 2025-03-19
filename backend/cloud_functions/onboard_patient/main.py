import uuid
import json
import functions_framework
import os
import requests
from google.cloud import firestore, storage, secretmanager
from datetime import datetime
import re

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

# Initialize Cloud Storage
storage_client = storage.Client()
bucket_name = "duoligo-pt-app-audio"  # Change to your actual bucket name for audio files

# Secret Manager setup
def access_secret_version(secret_id, version_id="latest"):
    """
    Access the secret from GCP Secret Manager
    """
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{os.environ['PROJECT_ID']}/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8").strip()

@functions_framework.http
def onboard_patient(request):
    """
    Cloud Function to handle patient onboarding.
    Receives data from the iOS app, parses it, and stores in Firestore.
    Also handles personalized audio generation when requested.
    
    Request format for onboarding:
    {
        "voice_input": "My name is John, I'm 45 years old. My knee hurts when I climb stairs, 
                        the pain is about 7 out of 10. I'd like to exercise daily. My goal is to play with my kids pain-free.",
        "fcm_token": "firebase-cloud-messaging-token"  // Optional, for notifications
    }
    
    Request format for personalized audio:
    {
        "prompt": "Generate a warm, friendly greeting for John from Pep the PT dog",
        "voice_id": "K1pm982Vbt7xCZM8zYWJ",  // ElevenLabs voice ID
        "stage": "name_confirmation"         // Used for organizing audio files
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
        
        if not request_json:
            return (json.dumps({'error': 'Invalid request - missing data'}, cls=DateTimeEncoder), 400, headers)
        
        # Determine what kind of request this is
        if 'prompt' in request_json:
            # This is a personalized audio generation request
            return generate_personalized_audio(request_json, headers)
        elif 'voice_input' in request_json:
            # This is a patient onboarding request
            return process_onboarding(request_json, headers)
        else:
            return (json.dumps({'error': 'Invalid request - unrecognized format'}, cls=DateTimeEncoder), 400, headers)
            
    except Exception as e:
        return (json.dumps({'error': f'Error processing request: {str(e)}'}, cls=DateTimeEncoder), 500, headers)


def process_onboarding(request_data, headers):
    """
    Process patient onboarding request
    """
    # Get the voice input and FCM token
    voice_input = request_data['voice_input']
    fcm_token = request_data.get('fcm_token', '')
    
    # Parse the voice input
    patient_data = parse_patient_data(voice_input)
    
    # Generate a unique ID for the patient
    patient_id = str(uuid.uuid4())
    
    # Create patient document
    patient_doc = {
        'id': patient_id,
        'name': patient_data['name'],
        'age': patient_data['age'],
        'exercise_frequency': patient_data['exercise_frequency'],
        'goal': patient_data.get('goal', ''),
        'fcm_token': fcm_token,
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
    
    # Return success response with patient ID and data
    response = {
        'status': 'success',
        'patient_id': patient_id,
        'patient_data': patient_data,
        'message': 'Patient successfully onboarded'
    }
    
    return (json.dumps(response, cls=DateTimeEncoder), 200, headers)


def generate_personalized_audio(request_data, headers):
    """
    Generate personalized audio using ElevenLabs API
    """
    prompt = request_data.get('prompt')
    voice_id = request_data.get('voice_id', 'K1pm982Vbt7xCZM8zYWJ')  # Default ElevenLabs voice
    stage = request_data.get('stage', 'generic')
    
    # Generate audio with ElevenLabs
    audio_data, error = generate_elevenlabs_audio(prompt, voice_id)
    
    if error:
        return (json.dumps({'error': f'Error generating audio: {error}'}, cls=DateTimeEncoder), 500, headers)
    
    # Upload audio to Cloud Storage
    audio_url = upload_audio_to_storage(audio_data, stage)
    
    if not audio_url:
        return (json.dumps({'error': 'Failed to upload audio to storage'}, cls=DateTimeEncoder), 500, headers)
    
    # Return success response with audio URL
    response = {
        'status': 'success',
        'audio_url': audio_url,
        'message': 'Audio generated successfully'
    }
    
    return (json.dumps(response, cls=DateTimeEncoder), 200, headers)


def generate_elevenlabs_audio(prompt, voice_id):
    """
    Generate audio using ElevenLabs API
    """
    try:
        # Get API key from Secret Manager or use the provided one
        try:
            elevenlabs_api_key = access_secret_version("elevenlabs-api-key")
        except:
            # Fall back to hardcoded key if secret isn't available
            elevenlabs_api_key = "sk_4e6e7a71506b1ecddce0c73e92a9563cdc454e60c102fef0"
        
        # Call ElevenLabs API
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_128"
        headers = {
            "xi-api-key": elevenlabs_api_key,
            "Content-Type": "application/json"
        }
        payload = {
            "text": prompt,
            "model_id": "eleven_multilingual_v2"
        }
        
        response = requests.post(url, headers=headers, json=payload)
        
        if response.status_code != 200:
            return None, f"ElevenLabs API error: {response.text}"
        
        # Return audio data
        return response.content, None
        
    except Exception as e:
        return None, str(e)


def upload_audio_to_storage(audio_data, stage):
    """
    Upload audio data to Google Cloud Storage and return public URL
    """
    try:
        # Create a unique filename
        filename = f"{stage}_{uuid.uuid4()}.mp3"
        blob_name = f"personalized-audio/{stage}/{filename}"
        
        # Get the bucket
        bucket = storage_client.bucket(bucket_name)
        
        # Create a new blob
        blob = bucket.blob(blob_name)
        
        # Upload the audio
        blob.upload_from_string(audio_data, content_type="audio/mpeg")
        
        # Make the blob publicly readable
        blob.make_public()
        
        # Return the public URL
        return blob.public_url
        
    except Exception as e:
        print(f"Error uploading to storage: {str(e)}")
        return None


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
    pain_match = re.search(r"(?:my|the)?\s*(?:knee|pain|ache|experience)(?:\s+|\-)?(?:is|feels|hurts)?\s*([^.]+)", voice_input, re.IGNORECASE)
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
    
    # Extract goal
    goal_match = re.search(r"(?:goal|aim|want|would like) (?:is |to )([^.]+)", voice_input, re.IGNORECASE)
    if goal_match:
        data['goal'] = goal_match.group(1).strip()
    
    return data