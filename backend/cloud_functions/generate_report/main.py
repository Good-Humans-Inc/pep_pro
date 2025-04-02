import functions_framework
import firebase_admin
from firebase_admin import credentials, firestore
import openai
import json
from datetime import datetime

# Initialize Firebase Admin
cred = credentials.Certificate('service-account.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

@functions_framework.http
def generate_pt_report(request):
    # Enable CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get request data
        request_json = request.get_json()
        patient_id = request_json.get('patient_id')
        exercise_id = request_json.get('exercise_id')
        conversation_history = request_json.get('conversation_history', [])
        
        if not patient_id or not exercise_id:
            return (json.dumps({'error': 'Missing required parameters'}), 400, headers)
        
        # Get exercise details from Firestore
        exercise_ref = db.collection('exercises').document(exercise_id)
        exercise_doc = exercise_ref.get()
        
        if not exercise_doc.exists:
            return (json.dumps({'error': 'Exercise not found'}), 404, headers)
            
        exercise_data = exercise_doc.to_dict()
        
        # Get patient's exercise history
        patient_history = db.collection('exercise_reports').where('patient_id', '==', patient_id).order_by('timestamp', direction=firestore.Query.DESCENDING).limit(5).get()
        recent_exercises = [doc.to_dict() for doc in patient_history]
        
        # Extract exercise metrics from conversation
        metrics = extract_exercise_metrics(conversation_history)
        
        # Format conversation history for GPT
        formatted_history = format_conversation_history(conversation_history)
        
        # Create GPT prompt
        prompt = f"""Based on the following exercise session conversation and patient history, generate a comprehensive physical therapy report:

Exercise: {exercise_data.get('name', 'Unknown')}
Date: {datetime.now().strftime('%Y-%m-%d')}

Exercise Metrics:
Sets Completed: {metrics['sets_completed']}
Reps Completed: {metrics['reps_completed']}
Exercise Duration: {metrics['duration_minutes']} minutes

Recent Exercise History:
{json.dumps(recent_exercises, indent=2)}

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

        # Call OpenAI API
        response = openai.ChatCompletion.create(
            model="gpt-4",
            messages=[
                {"role": "system", "content": """You are a professional physical therapist assistant. 
                Generate detailed, accurate reports based on exercise session conversations.
                Focus on specific, actionable insights and maintain a supportive, encouraging tone.
                Consider the patient's history and progress when providing feedback.
                Be precise about exercise metrics and ensure they match what was discussed in the conversation."""},
                {"role": "user", "content": prompt}
            ],
            temperature=0.7,
            max_tokens=1000
        )
        
        # Parse GPT response
        report_data = json.loads(response.choices[0].message.content)
        
        # Ensure the metrics match what we extracted
        report_data['sets_completed'] = metrics['sets_completed']
        report_data['reps_completed'] = metrics['reps_completed']
        
        # Store report in Firestore
        report_ref = db.collection('exercise_reports').document()
        report_data.update({
            'patient_id': patient_id,
            'exercise_id': exercise_id,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'exercise_name': exercise_data.get('name', 'Unknown'),
            'exercise_description': exercise_data.get('description', ''),
            'target_joints': exercise_data.get('target_joints', []),
            'instructions': exercise_data.get('instructions', []),
            'duration_minutes': metrics['duration_minutes']
        })
        report_ref.set(report_data)
        
        return (json.dumps({
            'status': 'success',
            'report_id': report_ref.id,
            'report': report_data
        }), 200, headers)
        
    except Exception as e:
        print(f"Error generating report: {str(e)}")
        return (json.dumps({'error': str(e)}), 500, headers)

def extract_exercise_metrics(conversation_history):
    """Extract exercise metrics from conversation history."""
    metrics = {
        'sets_completed': 0,
        'reps_completed': 0,
        'duration_minutes': 0
    }
    
    # Initialize variables to track the latest metrics mentioned
    for message in conversation_history:
        content = message.get('content', '').lower()
        
        # Look for sets completed
        if 'set' in content or 'sets' in content:
            # Try to find numbers followed by "set" or "sets"
            import re
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

def format_conversation_history(conversation_history):
    """Format conversation history for better GPT analysis."""
    formatted_messages = []
    for msg in conversation_history:
        role = msg.get('role', '')
        content = msg.get('content', '')
        speaker = 'Patient' if role == 'user' else 'AI Coach'
        formatted_messages.append(f"{speaker}: {content}")
    
    return "\n".join(formatted_messages) 