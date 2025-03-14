import functions_framework
import json
import uuid
import os
import requests
from google.cloud import firestore, storage, secretmanager
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

# Secret Manager setup
def access_secret_version(secret_id, version_id="latest"):
    """
    Access the secret from GCP Secret Manager
    """
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{os.environ['PROJECT_ID']}/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def add_custom_exercise(request):
    """
    Cloud Function for physical therapists to add custom exercises.
    
    Request format:
    {
        "pt_id": "uuid-of-pt",
        "patient_id": "uuid-of-patient",
        "exercise_name": "Single-Leg Balance",
        "llm_provider": "claude" or "openai",
        "custom_video": {
            "base64_data": "base64-encoded-video-data",
            "content_type": "video/mp4",
            "filename": "exercise-video.mp4"
        },
        "voice_instructions": "The patient should stand on one leg..."
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
        
        if not request_json or 'exercise_name' not in request_json:
            return (json.dumps({'error': 'Invalid request - missing exercise_name'}, cls=DateTimeEncoder), 400, headers)
        
        pt_id = request_json.get('pt_id')
        patient_id = request_json.get('patient_id')
        exercise_name = request_json.get('exercise_name')
        llm_provider = request_json.get('llm_provider', 'claude')  # Default to Claude if not specified
        custom_video = request_json.get('custom_video')
        voice_instructions = request_json.get('voice_instructions', '')
        
        # 1. First, check if a similar exercise already exists
        similar_exercises = db.collection('exercises').where('name', '==', exercise_name).limit(1).get()
        
        if len(similar_exercises) > 0:
            # Use existing exercise as a starting point
            existing_exercise = similar_exercises[0].to_dict()
            exercise_data = existing_exercise.copy()
            exercise_data['original_exercise_id'] = existing_exercise['id']
        else:
            # Use LLM to generate exercise details based on name and any voice instructions
            if llm_provider == 'openai':
                exercise_data = generate_exercise_with_openai(exercise_name, voice_instructions)
            else:  # Default to Claude
                exercise_data = generate_exercise_with_claude(exercise_name, voice_instructions)
        
        # 2. Generate a new ID for this custom exercise
        exercise_id = str(uuid.uuid4())
        exercise_data['id'] = exercise_id
        
        # 3. If a custom video was provided, upload it to Cloud Storage
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
                
            except Exception as e:
                return (json.dumps({'error': f'Error uploading video: {str(e)}'}, cls=DateTimeEncoder), 500, headers)
        
        # 4. Update exercise data with video URL and metadata
        exercise_data.update({
            'video_url': video_url if video_url else exercise_data.get('video_url', ''),
            'is_template': False,
            'source': 'pt-created',
            'created_at': datetime.now(),
            'created_by': pt_id
        })
        
        # 5. Save the exercise to Firestore
        db.collection('exercises').document(exercise_id).set(exercise_data)
        
        # 6. Create patient-exercise link
        patient_exercise_id = str(uuid.uuid4())
        patient_exercise = {
            'id': patient_exercise_id,
            'patient_id': patient_id,
            'exercise_id': exercise_id,
            'recommended_at': datetime.now(),
            'pt_modified': True,
            'pt_id': pt_id,
            'frequency': 'daily',  # Default
            'sets': 3,             # Default
            'repetitions': 10      # Default
        }
        
        db.collection('patient_exercises').document(patient_exercise_id).set(patient_exercise)
        
        # 7. Return success response
        response = {
            'status': 'success',
            'exercise': exercise_data,
            'patient_exercise': patient_exercise,
            'message': 'Custom exercise successfully added'
        }
        
        return (json.dumps(response, cls=DateTimeEncoder), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': f'Error adding custom exercise: {str(e)}'}, cls=DateTimeEncoder), 500, headers)


def generate_exercise_with_claude(exercise_name, voice_instructions=""):
    """
    Generate exercise details using Anthropic's Claude API
    """
    # Get API key from Secret Manager
    api_key = access_secret_version("anthropic-api-key")
    
    # Construct prompt for Claude
    prompt = f"""
    I need detailed information about a knee rehabilitation exercise called "{exercise_name}".
    
    Additional instructions from the physical therapist:
    {voice_instructions}
    
    Please provide:
    1. A concise description of the exercise
    2. Target joints it affects
    3. Step-by-step instructions
    4. A URL for a representative video if you know of one
    
    Format your response as JSON according to this structure:
    ```json
    {{
      "name": "{exercise_name}",
      "description": "Brief description of the exercise",
      "target_joints": ["knee", "ankle"],
      "instructions": [
        "Step 1",
        "Step 2",
        "Step 3"
      ],
      "video_url": "https://example.com/video.mp4"
    }}
    ```
    
    Respond ONLY with the JSON object and nothing else.
    """
    
    # Call Claude API
    response = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        },
        json={
            "model": "claude-3-opus-20240229",
            "max_tokens": 1000,
            "temperature": 0.3,
            "system": "You are a senior physical therapist specializing in knee rehabilitation.",
            "messages": [
                {"role": "user", "content": prompt}
            ]
        }
    )
    
    # Parse response
    if response.status_code != 200:
        raise Exception(f"Claude API error: {response.text}")
    
    result = response.json()
    content = result.get('content', [{}])[0].get('text', '{}')
    
    # Extract JSON from the response
    import re
    json_match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
    
    if json_match:
        exercise_json = json_match.group(1)
    else:
        exercise_json = content  # Assume the content is just JSON
    
    exercise = json.loads(exercise_json)
    
    # Ensure target_joints is a list
    if isinstance(exercise.get('target_joints', []), str):
        exercise['target_joints'] = exercise['target_joints'].split(',')
    
    # Ensure instructions is a list
    if isinstance(exercise.get('instructions', []), str):
        exercise['instructions'] = exercise['instructions'].split(';')
    
    return exercise


def generate_exercise_with_openai(exercise_name, voice_instructions=""):
    """
    Generate exercise details using OpenAI's GPT API
    """
    # Get API key from Secret Manager
    api_key = access_secret_version("openai-api-key")
    
    # Construct prompt similar to Claude version
    prompt = f"""
    I need detailed information about a knee rehabilitation exercise called "{exercise_name}".
    
    Additional instructions from the physical therapist:
    {voice_instructions}
    
    Please provide:
    1. A concise description of the exercise
    2. Target joints it affects
    3. Step-by-step instructions
    4. A URL for a representative video if you know of one
    
    Format your response as JSON according to this structure:
    {{
      "name": "{exercise_name}",
      "description": "Brief description of the exercise",
      "target_joints": ["knee", "ankle"],
      "instructions": [
        "Step 1",
        "Step 2",
        "Step 3"
      ],
      "video_url": "https://example.com/video.mp4"
    }}
    
    Respond ONLY with the JSON object and nothing else.
    """
    
    # Call OpenAI API
    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        },
        json={
            "model": "gpt-4",
            "messages": [
                {"role": "system", "content": "You are a senior physical therapist specializing in knee rehabilitation."},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.3,
            "max_tokens": 1000
        }
    )
    
    # Parse response
    if response.status_code != 200:
        raise Exception(f"OpenAI API error: {response.text}")
    
    result = response.json()
    content = result.get('choices', [{}])[0].get('message', {}).get('content', '{}')
    
    exercise = json.loads(content)
    
    # Ensure target_joints is a list
    if isinstance(exercise.get('target_joints', []), str):
        exercise['target_joints'] = exercise['target_joints'].split(',')
    
    # Ensure instructions is a list
    if isinstance(exercise.get('instructions', []), str):
        exercise['instructions'] = exercise['instructions'].split(';')
    
    return exercise