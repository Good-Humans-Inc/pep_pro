import functions_framework
import json
import uuid
import os
import requests
import logging
import re  # Add missing import for regex
from datetime import datetime
from google.cloud import firestore
from google.cloud import secretmanager

# Set up logging with more detailed format
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('generate_pt_report')

# Custom JSON encoder to handle datetime objects
class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        # Handle Firestore's DatetimeWithNanoseconds
        if hasattr(obj, 'isoformat'):
            return obj.isoformat()
        return super(DateTimeEncoder, self).default(obj)

# Secret Manager setup
def access_secret_version(secret_id, version_id="latest"):
    """
    Access the secret from GCP Secret Manager
    """
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{os.environ['PROJECT_ID']}/secrets/{secret_id}/versions/{version_id}"
        response = client.access_secret_version(request={"name": name})
        # Strip whitespace and newlines to avoid issues with API keys
        return response.payload.data.decode("UTF-8").strip()
    except Exception as e:
        logger.error(f"Error accessing secret '{secret_id}': {str(e)}")
        raise

# Initialize Firestore DB with error handling
try:
    db = firestore.Client()
    logger.info("Successfully initialized Firestore client")
except Exception as e:
    logger.error(f"Failed to initialize Firestore client: {str(e)}")
    raise

def extract_exercise_metrics(conversation_history):
    """Extract exercise metrics from conversation history."""
    metrics = {
        'sets_completed': 0,
        'reps_completed': 0,
        'duration_minutes': 0
    }
    
    try:
        for message in conversation_history:
            content = message.get('content', '').lower()
            
            # Look for sets completed
            if 'set' in content or 'sets' in content:
                set_matches = re.findall(r'(\d+)\s*sets?', content)
                if set_matches:
                    metrics['sets_completed'] = max(metrics['sets_completed'], int(set_matches[-1]))
            
            # Look for reps completed
            if 'rep' in content or 'reps' in content:
                rep_matches = re.findall(r'(\d+)\s*reps?', content)
                if rep_matches:
                    metrics['reps_completed'] = max(metrics['reps_completed'], int(rep_matches[-1]))
            
            # Look for duration
            if 'minute' in content or 'minutes' in content:
                duration_matches = re.findall(r'(\d+)\s*minutes?', content)
                if duration_matches:
                    metrics['duration_minutes'] = max(metrics['duration_minutes'], int(duration_matches[-1]))
        
        return metrics
    except Exception as e:
        logger.error(f"Error extracting exercise metrics: {str(e)}")
        return metrics

def format_conversation_history(conversation_history):
    """Format conversation history for better GPT analysis."""
    try:
        formatted_messages = []
        for msg in conversation_history:
            role = msg.get('role', '')
            content = msg.get('content', '')
            speaker = 'Patient' if role == 'user' else 'AI Coach'
            formatted_messages.append(f"{speaker}: {content}")
        
        return "\n".join(formatted_messages)
    except Exception as e:
        logger.error(f"Error formatting conversation history: {str(e)}")
        return "Error formatting conversation history"

def generate_report_with_openai(exercise_data, patient_history, metrics, formatted_history, api_key):
    """Generate report using OpenAI's GPT API."""
    try:
        prompt = f"""Based on the following exercise session conversation and patient history, generate a comprehensive physical therapy report:

Exercise: {exercise_data.get('name', 'Unknown')}
Date: {datetime.now().strftime('%Y-%m-%d')}

Exercise Metrics:
Sets Completed: {metrics['sets_completed']}
Reps Completed: {metrics['reps_completed']}
Exercise Duration: {metrics['duration_minutes']} minutes

Recent Exercise History:
{json.dumps(patient_history, cls=DateTimeEncoder, indent=2)}

Conversation History:
{formatted_history}

Please analyze the conversation and provide a detailed report including:

1. General Feeling: Patient's overall experience, comfort level, and engagement during the session
2. Performance Quality: Detailed assessment of exercise execution, form, and technique
3. Pain Report: Any pain or discomfort reported, including location, intensity, and duration
4. Completion Status: Whether the exercise was completed as prescribed, including any modifications or adjustments
5. Sets and Reps Completed: Actual exercise volume and any variations from prescribed
6. Day Streak: Current streak information and consistency patterns
7. Motivational Message: Personalized encouragement based on performance and progress

Consider the patient's recent exercise history when generating the report to provide context and track progress.

Format the response as JSON with these exact keys:
{{
    "general_feeling": "string",
    "performance_quality": "string",
    "pain_report": "string",
    "completed": boolean,
    "sets_completed": integer,
    "reps_completed": integer,
    "day_streak": integer,
    "motivational_message": "string"
}}"""

        response = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            },
            json={
                "model": "gpt-4",
                "messages": [
                    {"role": "system", "content": """You are a professional physical therapist assistant. 
                    Generate detailed, accurate reports based on exercise session conversations.
                    Focus on specific, actionable insights and maintain a supportive, encouraging tone.
                    Consider the patient's history and progress when providing feedback.
                    Be precise about exercise metrics and ensure they match what was discussed in the conversation."""},
                    {"role": "user", "content": prompt}
                ],
                "temperature": 0.7,
                "max_tokens": 1000
            }
        )
        
        if response.status_code != 200:
            raise Exception(f"OpenAI API error: {response.text}")
        
        result = response.json()
        content = result.get('choices', [{}])[0].get('message', {}).get('content', '{}')
        return json.loads(content)
    except Exception as e:
        logger.error(f"Error generating report with OpenAI: {str(e)}")
        raise

@functions_framework.http
def generate_report(request):
    """
    Cloud Function to generate a physical therapy report based on exercise session data.
    
    Request format:
    {
        "patient_id": "uuid-of-patient",
        "patient_exercise_id": "uuid-of-patient-exercise",
        "conversation_history": [
            {"role": "user", "content": "message"},
            {"role": "ai", "content": "message"}
        ]
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
        
        if not request_json or 'patient_id' not in request_json or 'patient_exercise_id' not in request_json:
            return (json.dumps({'error': 'Invalid request - missing required parameters'}, cls=DateTimeEncoder), 400, headers)
        
        patient_id = request_json['patient_id']
        patient_exercise_id = request_json['patient_exercise_id']
        conversation_history = request_json.get('conversation_history', [])
        
        logger.info(f"Processing report generation for patient_id: {patient_id}, patient_exercise_id: {patient_exercise_id}")
        
        # Get patient exercise details from Firestore
        patient_exercise_ref = db.collection('patient_exercises').document(patient_exercise_id)
        patient_exercise_doc = patient_exercise_ref.get()
        
        if not patient_exercise_doc.exists:
            logger.warning(f"Patient exercise not found: {patient_exercise_id}")
            return (json.dumps({'error': 'Patient exercise not found'}, cls=DateTimeEncoder), 404, headers)
            
        patient_exercise_data = patient_exercise_doc.to_dict()
        
        # Get the base exercise details
        exercise_id = patient_exercise_data.get('exercise_id')
        if not exercise_id:
            logger.warning(f"No exercise_id found in patient exercise: {patient_exercise_id}")
            return (json.dumps({'error': 'No exercise_id found in patient exercise'}, cls=DateTimeEncoder), 404, headers)
            
        exercise_ref = db.collection('exercises').document(exercise_id)
        exercise_doc = exercise_ref.get()
        
        if not exercise_doc.exists:
            logger.warning(f"Base exercise not found: {exercise_id}")
            return (json.dumps({'error': 'Base exercise not found'}, cls=DateTimeEncoder), 404, headers)
            
        exercise_data = exercise_doc.to_dict()
        
        # Get patient's exercise history
        patient_history = db.collection('exercise_reports').where('patient_id', '==', patient_id).order_by('timestamp', direction=firestore.Query.DESCENDING).limit(5).get()
        recent_exercises = [doc.to_dict() for doc in patient_history]
        
        # Extract exercise metrics from conversation
        metrics = extract_exercise_metrics(conversation_history)
        
        # Format conversation history for GPT
        formatted_history = format_conversation_history(conversation_history)
        
        # Get OpenAI API key from Secret Manager
        api_key = access_secret_version("openai-api-key")
        
        # Generate report using OpenAI
        report_data = generate_report_with_openai(exercise_data, recent_exercises, metrics, formatted_history, api_key)
        
        # Ensure the metrics match what we extracted
        report_data['sets_completed'] = metrics['sets_completed']
        report_data['reps_completed'] = metrics['reps_completed']
        
        # Store report in Firestore
        report_ref = db.collection('exercise_reports').document()
        
        # Create the report data without the timestamp first
        report_data_to_store = {
            'patient_id': patient_id,
            'patient_exercise_id': patient_exercise_id,
            'exercise_id': exercise_id,
            'exercise_name': exercise_data.get('name', 'Unknown'),
            'exercise_description': exercise_data.get('description', ''),
            'target_joints': exercise_data.get('target_joints', []),
            'instructions': exercise_data.get('instructions', []),
            'duration_minutes': metrics['duration_minutes'],
            'frequency': patient_exercise_data.get('frequency', 'daily'),
            'sets': patient_exercise_data.get('sets', 3),
            'repetitions': patient_exercise_data.get('repetitions', 10),
            'notes': patient_exercise_data.get('notes', '')
        }
        
        # Add the report data from OpenAI
        report_data_to_store.update(report_data)
        
        # Store in Firestore with server timestamp
        report_ref.set({
            **report_data_to_store,
            'timestamp': firestore.SERVER_TIMESTAMP
        })
        
        logger.info(f"Successfully generated and stored report for patient {patient_id}")
        
        # For the response, use current timestamp since we can't serialize SERVER_TIMESTAMP
        response_data = {
            'status': 'success',
            'report_id': report_ref.id,
            'report': {
                **report_data_to_store,
                'timestamp': datetime.now().isoformat()
            }
        }
        
        return (json.dumps(response_data, cls=DateTimeEncoder), 200, headers)
        
    except Exception as e:
        logger.error(f"Error generating report: {str(e)}", exc_info=True)
        return (json.dumps({'error': f'Error generating report: {str(e)}'}, cls=DateTimeEncoder), 500, headers) 