import unittest
from unittest.mock import patch, MagicMock
from backend.cloud_functions.generate_reprot.main import generate_pt_report, extract_exercise_metrics, format_conversation_history

class TestGeneratePTReport(unittest.TestCase):
    def setUp(self):
        self.mock_request = MagicMock()
        self.mock_request.method = 'POST'
        self.mock_request.get_json.return_value = {
            'patient_id': 'test_patient_123',
            'exercise_id': 'test_exercise_456',
            'conversation_history': [
                {'role': 'user', 'content': 'I completed 3 sets of 10 reps'},
                {'role': 'ai', 'content': 'Great job! How are you feeling?'},
                {'role': 'user', 'content': 'I feel good, no pain'},
                {'role': 'ai', 'content': 'That\'s excellent! Keep up the good work.'}
            ]
        }

    @patch('generate_pt_report.firestore')
    @patch('generate_pt_report.openai')
    def test_generate_pt_report_success(self, mock_openai, mock_firestore):
        # Mock Firestore responses
        mock_exercise_doc = MagicMock()
        mock_exercise_doc.exists = True
        mock_exercise_doc.to_dict.return_value = {
            'name': 'Test Exercise',
            'description': 'Test Description',
            'target_joints': ['knee'],
            'instructions': ['Step 1', 'Step 2']
        }
        
        mock_firestore.client.return_value.collection.return_value.document.return_value.get.return_value = mock_exercise_doc
        
        # Mock OpenAI response
        mock_openai.ChatCompletion.create.return_value.choices = [
            MagicMock(message=MagicMock(content='''
            {
                "general_feeling": "Patient reported feeling good",
                "performance_quality": "Good form maintained",
                "pain_report": "No pain reported",
                "completed": true,
                "sets_completed": 3,
                "reps_completed": 10,
                "day_streak": 1,
                "motivational_message": "Great work!"
            }
            '''))
        ]
        
        # Call the function
        response, status_code, headers = generate_pt_report(self.mock_request)
        
        # Assertions
        self.assertEqual(status_code, 200)
        self.assertIn('status', response)
        self.assertEqual(response['status'], 'success')
        self.assertIn('report', response)
        self.assertEqual(response['report']['sets_completed'], 3)
        self.assertEqual(response['report']['reps_completed'], 10)

    def test_extract_exercise_metrics(self):
        conversation = [
            {'role': 'user', 'content': 'I did 3 sets of 10 reps'},
            {'role': 'ai', 'content': 'Great! Now do 4 sets'},
            {'role': 'user', 'content': 'I completed the exercise in 15 minutes'}
        ]
        
        metrics = extract_exercise_metrics(conversation)
        
        self.assertEqual(metrics['sets_completed'], 4)
        self.assertEqual(metrics['reps_completed'], 10)
        self.assertEqual(metrics['duration_minutes'], 15)

    def test_format_conversation_history(self):
        conversation = [
            {'role': 'user', 'content': 'Hello'},
            {'role': 'ai', 'content': 'Hi there!'}
        ]
        
        formatted = format_conversation_history(conversation)
        
        self.assertIn('Patient: Hello', formatted)
        self.assertIn('AI Coach: Hi there!', formatted)

    def test_generate_pt_report_missing_params(self):
        # Test with missing patient_id
        self.mock_request.get_json.return_value = {
            'exercise_id': 'test_exercise_456',
            'conversation_history': []
        }
        
        response, status_code, headers = generate_pt_report(self.mock_request)
        
        self.assertEqual(status_code, 400)
        self.assertIn('error', response)

if __name__ == '__main__':
    unittest.main() 