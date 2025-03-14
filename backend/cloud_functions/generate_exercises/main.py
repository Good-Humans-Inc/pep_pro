import functions_framework
import json
import uuid
import os
import requests
import re
from google.cloud import firestore
from google.cloud import secretmanager
from datetime import datetime

# Custom JSON encoder to handle datetime objects
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super(DateTimeEncoder, self).default(obj)

# Secret Manager setup
def access_secret_version(secret_id, version_id="latest"):
    """
    Access the secret from GCP Secret Manager
    """
    client = secret_manager.SecretManagerServiceClient()
    name = f"projects/{os.environ['PROJECT_ID']}/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    # Strip whitespace and newlines to avoid issues with API keys
    return response.payload.data.decode("UTF-8").strip()

# Initialize Firestore DB with explicit project and database
db = firestore.Client(project='pep-pro', database='pep-pro')

@functions_framework.http
def generate_exercises(request):
    """
    Cloud Function to generate exercises for a patient using LLM.
    
    Request format:
    {
        "patient_id": "uuid-of-patient",
        "llm_provider": "claude" or "openai"
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
            return (json.dumps({'error': 'Invalid request - missing patient_id'}, cls=DateTimeEncoder), 400, headers)
        
        patient_id = request_json['patient_id']
        llm_provider = request_json.get('llm_provider', 'claude')  # Default to Claude if not specified
        
        # 1. First, check if suitable exercises already exist in the database
        existing_exercises = check_existing_exercises(patient_id)
        
        if existing_exercises and len(existing_exercises) >= 3:
            return (json.dumps({
                'status': 'success', 
                'exercises': existing_exercises,
                'source': 'database'
            }, cls=DateTimeEncoder), 200, headers)
        
        # 2. If not enough existing exercises, get patient data
        patient_data = get_patient_data(patient_id)
        if not patient_data:
            return (json.dumps({'error': 'Patient not found'}, cls=DateTimeEncoder), 404, headers)
        
        # 3. Generate exercises using LLM
        if llm_provider == 'openai':
            exercises = generate_exercises_with_openai(patient_data)
        else:  # Default to Claude
            exercises = generate_exercises_with_claude(patient_data)
        
        # 4. Save the generated exercises to Firestore
        saved_exercises = save_exercises(exercises, patient_id)
        
        # 5. Return the exercises
        return (json.dumps({
            'status': 'success',
            'exercises': saved_exercises,
            'source': 'llm-generated'
        }, cls=DateTimeEncoder), 200, headers)
        
    except Exception as e:
        return (json.dumps({'error': f'Error generating exercises: {str(e)}'}, cls=DateTimeEncoder), 500, headers)


def check_existing_exercises(patient_id):
    """
    Check if suitable exercises already exist in the database for this patient
    or similar patients with matching pain points
    """
    # First check if this patient already has assigned exercises
    existing_assignments = db.collection('patient_exercises').where('patient_id', '==', patient_id).get()
    
    if len(existing_assignments) > 0:
        # Patient has existing exercise assignments, fetch those exercise details
        existing_exercise_ids = [doc.to_dict()['exercise_id'] for doc in existing_assignments]
        exercises = []
        
        for ex_id in existing_exercise_ids:
            ex_doc = db.collection('exercises').document(ex_id).get()
            if ex_doc.exists:
                ex_data = ex_doc.to_dict()
                exercises.append(ex_data)
        
        if len(exercises) >= 3:
            return exercises
    
    # If not enough exercises found, look for similar patients
    # Get this patient's pain points
    pain_points = db.collection('pain_points').where('patient_id', '==', patient_id).get()
    
    if len(pain_points) == 0:
        return []  # No pain points to compare
    
    # For simplicity in this demo, we'll just return some template exercises
    # In a production app, you'd implement similarity matching logic here
    template_exercises = db.collection('exercises').where('is_template', '==', True).limit(5).get()
    
    return [doc.to_dict() for doc in template_exercises]


def get_patient_data(patient_id):
    """
    Retrieve patient data and pain points from Firestore
    """
    # Get patient document
    patient_doc = db.collection('patients').document(patient_id).get()
    
    if not patient_doc.exists:
        return None
    
    patient_data = patient_doc.to_dict()
    
    # Get patient's pain points
    pain_points = db.collection('pain_points').where('patient_id', '==', patient_id).get()
    patient_data['pain_points'] = [doc.to_dict() for doc in pain_points]
    
    return patient_data


def generate_exercises_with_claude(patient_data):
    """
    Generate exercises using Anthropic's Claude API
    """
    try:
        # Get API key from Secret Manager
        api_key = access_secret_version("anthropic-api-key")
        
        # Construct prompt for Claude
        name = patient_data.get('name', 'the patient')
        age = patient_data.get('age', 'unknown age')
        frequency = patient_data.get('exercise_frequency', 'daily')
        
        pain_points_text = "No specific pain points mentioned."
        if 'pain_points' in patient_data and len(patient_data['pain_points']) > 0:
            pain_descriptions = [f"{pp.get('description', 'knee pain')} (severity: {pp.get('severity', 5)}/10)" 
                               for pp in patient_data['pain_points']]
            pain_points_text = "Pain points: " + "; ".join(pain_descriptions)
        
        prompt = f"""
        I need to generate personalized knee rehabilitation exercises for a patient with the following profile:
        
        Name: {name}
        Age: {age}
        Exercise frequency: {frequency}
        {pain_points_text}
        
        Please provide 3-5 evidence-based exercises appropriate for knee rehabilitation for this specific patient.
        Consider standard physical therapy protocols and clinical practice guidelines.
        
        For each exercise, include:
        1. A clear name
        2. A concise description
        3. Target joints (comma-separated list)
        4. Step-by-step instructions (semicolon-separated list)
        5. A URL for a representative video if available
        
        Format your response as JSON according to this structure:
        ```json
        [
          {{
            "name": "Exercise Name",
            "description": "Brief description of the exercise",
            "target_joints": ["knee", "ankle"],
            "instructions": [
              "Step 1",
              "Step 2",
              "Step 3"
            ],
            "video_url": "https://example.com/video.mp4"
          }}
        ]
        ```
        
        Respond ONLY with the JSON array and nothing else.
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
                "max_tokens": 2000,
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
        content = result.get('content', [{}])[0].get('text', '[]')
        
        # Extract JSON from the response
        json_match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
        
        if json_match:
            exercises_json = json_match.group(1)
        else:
            exercises_json = content  # Assume the content is just JSON
        
        exercises = json.loads(exercises_json)
        return exercises
    except Exception as e:
        raise Exception(f"Error in generate_exercises_with_claude: {str(e)}")


def generate_exercises_with_openai(patient_data):
    """
    Generate exercises using OpenAI's GPT API
    """
    try:
        # Get API key from Secret Manager
        api_key = access_secret_version("openai-api-key")
        
        # Construct prompt similarly to Claude version
        name = patient_data.get('name', 'the patient')
        age = patient_data.get('age', 'unknown age')
        frequency = patient_data.get('exercise_frequency', 'daily')
        
        pain_points_text = "No specific pain points mentioned."
        if 'pain_points' in patient_data and len(patient_data['pain_points']) > 0:
            pain_descriptions = [f"{pp.get('description', 'knee pain')} (severity: {pp.get('severity', 5)}/10)" 
                               for pp in patient_data['pain_points']]
            pain_points_text = "Pain points: " + "; ".join(pain_descriptions)
        
        prompt = f"""
        I need to generate personalized knee rehabilitation exercises for a patient with the following profile:
        
        Name: {name}
        Age: {age}
        Exercise frequency: {frequency}
        {pain_points_text}
        
        Please provide 3-5 evidence-based exercises appropriate for knee rehabilitation for this specific patient.
        Consider standard physical therapy protocols and clinical practice guidelines.
        
        For each exercise, include:
        1. A clear name
        2. A concise description
        3. Target joints (comma-separated list)
        4. Step-by-step instructions (semicolon-separated list)
        5. A URL for a representative video if available
        
        Format your response as JSON according to this structure:
        [
          {{
            "name": "Exercise Name",
            "description": "Brief description of the exercise",
            "target_joints": ["knee", "ankle"],
            "instructions": [
              "Step 1",
              "Step 2",
              "Step 3"
            ],
            "video_url": "https://example.com/video.mp4"
          }}
        ]
        
        Respond ONLY with the JSON array and nothing else.
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
                "max_tokens": 2000
            }
        )
        
        # Parse response
        if response.status_code != 200:
            raise Exception(f"OpenAI API error: {response.text}")
        
        result = response.json()
        content = result.get('choices', [{}])[0].get('message', {}).get('content', '[]')
        
        exercises = json.loads(content)
        return exercises
    except Exception as e:
        raise Exception(f"Error in generate_exercises_with_openai: {str(e)}")


def save_exercises(exercises, patient_id):
    """
    Save generated exercises to Firestore and link them to the patient
    """
    saved_exercises = []
    
    for exercise in exercises:
        # Check if a similar exercise already exists
        similar_exercises = db.collection('exercises').where('name', '==', exercise['name']).limit(1).get()
        
        if len(similar_exercises) > 0:
            # Use existing exercise
            exercise_id = similar_exercises[0].id
            exercise_data = similar_exercises[0].to_dict()
        else:
            # Create new exercise
            exercise_id = str(uuid.uuid4())
            
            # Format the instructions as an array if it's not already
            if isinstance(exercise['instructions'], str):
                exercise['instructions'] = exercise['instructions'].split(';')
            
            # Ensure target_joints is a list
            if isinstance(exercise['target_joints'], str):
                exercise['target_joints'] = exercise['target_joints'].split(',')
                
            exercise_data = {
                'id': exercise_id,
                'name': exercise['name'],
                'description': exercise['description'],
                'target_joints': exercise['target_joints'],
                'instructions': exercise['instructions'],
                'video_url': exercise.get('video_url', ''),
                'created_at': datetime.now(),
                'is_template': False,
                'source': 'llm-generated'
            }
            
            # Save to Firestore
            db.collection('exercises').document(exercise_id).set(exercise_data)
        
        # Create patient-exercise link
        patient_exercise_id = str(uuid.uuid4())
        patient_exercise = {
            'id': patient_exercise_id,
            'patient_id': patient_id,
            'exercise_id': exercise_id,
            'recommended_at': datetime.now(),
            'pt_modified': False,
            'pt_id': None,
            'frequency': 'daily',  # Default, can be modified by PT
            'sets': 3,             # Default, can be modified by PT
            'repetitions': 10      # Default, can be modified by PT
        }
        
        db.collection('patient_exercises').document(patient_exercise_id).set(patient_exercise)
        saved_exercises.append(exercise_data)
    
    return saved_exercises