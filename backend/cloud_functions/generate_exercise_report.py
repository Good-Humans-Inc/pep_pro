import functions_framework
from google.cloud import firestore
import json
from datetime import datetime
import openai

@functions_framework.http
def generate_exercise_report(request):
    """Generate exercise report from conversation content."""
    
    # Set CORS headers for the preflight request
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)

    # Set CORS headers for the main request
    headers = {
        'Access-Control-Allow-Origin': '*'
    }

    try:
        request_json = request.get_json()
        
        if not request_json:
            return ('No data provided', 400, headers)

        # Extract required fields
        conversation_content = request_json.get('conversation_content')
        patient_id = request_json.get('patient_id')
        exercise_id = request_json.get('exercise_id')
        
        if not all([conversation_content, patient_id, exercise_id]):
            return ('Missing required fields', 400, headers)

        # Initialize Firestore client
        db = firestore.Client()

        # Use OpenAI to analyze conversation and generate report data
        analysis_prompt = f"""
        Analyze the following exercise conversation and extract key information for a report:
        {conversation_content}

        Generate a structured report with the following information:
        1. General feeling during exercise
        2. Performance quality assessment
        3. Pain report (if any)
        4. Number of sets and reps completed
        5. Whether the exercise was fully completed
        6. A motivational message based on the performance

        Format the response as a JSON object with these fields:
        - general_feeling
        - performance_quality
        - pain_report
        - sets_completed (number)
        - reps_completed (number)
        - completed (boolean)
        - motivational_message
        """

        response = openai.ChatCompletion.create(
            model="gpt-4",
            messages=[
                {"role": "system", "content": "You are an AI exercise analysis assistant that extracts structured information from exercise conversations."},
                {"role": "user", "content": analysis_prompt}
            ]
        )

        # Parse the AI-generated report
        report_data = json.loads(response.choices[0].message.content)

        # Add additional metadata
        report_data.update({
            'patient_id': patient_id,
            'exercise_id': exercise_id,
            'timestamp': datetime.utcnow().isoformat(),
            'day_streak': 1  # This should be calculated based on user's history
        })

        # Store report in Firestore
        reports_ref = db.collection('exercise_reports')
        report_ref = reports_ref.document()
        report_ref.set(report_data)

        # Return the report data
        return (json.dumps({
            'status': 'success',
            'report': report_data
        }), 200, headers)

    except Exception as e:
        print(f"Error generating report: {str(e)}")
        return (json.dumps({
            'status': 'error',
            'error': str(e)
        }), 500, headers) 