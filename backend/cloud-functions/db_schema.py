from google.cloud import firestore
import uuid
from datetime import datetime

def init_firestore_db():
    """
    Creates Firestore database structure (collections and example documents)
    """
    db = firestore.Client()
    
    # Define the database schema - Firestore is NoSQL but we'll define expected fields
    
    # Example document for patients collection
    patient_schema = {
        "id": "uuid-string",
        "name": "Patient Name",
        "age": 45,
        "exercise_frequency": "daily", # or "3x-weekly", "weekly", etc.
        "created_at": datetime.now(),
        "updated_at": datetime.now()
    }
    
    # Example document for pain_points collection
    pain_point_schema = {
        "id": "uuid-string",
        "patient_id": "patient-uuid-reference",
        "description": "Pain behind kneecap when climbing stairs",
        "severity": 7,  # 1-10 scale
        "created_at": datetime.now()
    }
    
    # Example document for exercises collection
    exercise_schema = {
        "id": "uuid-string",
        "name": "Knee Flexion",
        "description": "Improve flexibility and range of motion in your knee",
        "target_joints": ["knee", "ankle"],
        "instructions": [
            "Sit on a chair with feet flat on the floor",
            "Slowly slide one foot back, bending your knee",
            "Hold for 5 seconds",
            "Return to starting position",
            "Repeat 10 times, then switch legs"
        ],
        "video_url": "https://storage.googleapis.com/duolingo-pt-videos/knee-flexion.mp4",
        "created_at": datetime.now(),
        "is_template": True,  # Flag for system-generated exercises vs PT custom
        "source": "llm-generated"  # or "pt-created", "system-template"
    }
    
    # Example document for patient_exercises collection (junction table)
    patient_exercise_schema = {
        "id": "uuid-string",
        "patient_id": "patient-uuid-reference",
        "exercise_id": "exercise-uuid-reference", 
        "recommended_at": datetime.now(),
        "pt_modified": False,
        "pt_id": None,  # PT who modified if applicable
        "frequency": "daily",
        "sets": 3,
        "repetitions": 10,
        "notes": "Start with lower intensity if knee feels stiff"
    }
    
    # Example document for exercise_sessions collection (tracking completed exercises)
    exercise_session_schema = {
        "id": "uuid-string",
        "patient_id": "patient-uuid-reference",
        "exercise_id": "exercise-uuid-reference",
        "duration": 180,  # in seconds
        "completed": True,
        "pain_level": 3,  # reported after exercise
        "notes": "Felt some discomfort at maximum bend",
        "created_at": datetime.now()
    }
    
    # Example document for physical_therapists collection
    pt_schema = {
        "id": "uuid-string",
        "name": "Dr. Smith",
        "credential": "DPT",
        "patients": ["patient-uuid-reference-1", "patient-uuid-reference-2"],
        "created_at": datetime.now()
    }
    
    # Example document for notifications collection
    notification_schema = {
        "id": "uuid-string",
        "patient_id": "patient-uuid-reference",
        "title": "Time for your exercises",
        "body": "Don't forget to complete your knee flexion exercises today",
        "scheduled_for": datetime.now(),
        "exercise_ids": ["exercise-uuid-1", "exercise-uuid-2"],
        "status": "scheduled",  # or "sent", "cancelled"
        "created_at": datetime.now()
    }
    
    print("Firestore database schema defined")
    return db