from flask import Flask, request, jsonify
import os
import sqlite3
import datetime
import uuid
import nltk
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from google.cloud import speech
from google.cloud import storage

# Download NLTK resources
nltk.download('punkt')
nltk.download('stopwords')

app = Flask(__name__)

# Initialize Google Cloud clients
speech_client = speech.SpeechClient()
storage_client = storage.Client()

# Configure your GCP bucket
BUCKET_NAME = "knee-recovery-app-storage"

# Database setup
DB_PATH = "patients_database.sqlite"

def init_db():
    """Initialize the SQLite database with necessary tables"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Patients table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS patients (
        id TEXT PRIMARY KEY,
        name TEXT,
        age INTEGER,
        created_at TIMESTAMP,
        updated_at TIMESTAMP
    )
    ''')
    
    # Pain points table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS pain_points (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        description TEXT,
        severity INTEGER,
        created_at TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients (id)
    )
    ''')
    
    # Exercises table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS exercises (
        id TEXT PRIMARY KEY,
        name TEXT,
        description TEXT,
        target_joints TEXT,
        instructions TEXT
    )
    ''')
    
    # Patient exercises table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS patient_exercises (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        exercise_id TEXT,
        recommended_at TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients (id),
        FOREIGN KEY (exercise_id) REFERENCES exercises (id)
    )
    ''')
    
    # Exercise sessions table
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS exercise_sessions (
        id TEXT PRIMARY KEY,
        patient_id TEXT,
        exercise_id TEXT,
        duration INTEGER,
        completed BOOLEAN,
        notes TEXT,
        created_at TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients (id),
        FOREIGN KEY (exercise_id) REFERENCES exercises (id)
    )
    ''')
    
    conn.commit()
    conn.close()

def populate_sample_exercises():
    """Add sample exercises to the database"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    exercises = [
        {
            "id": str(uuid.uuid4()),
            "name": "Knee Flexion",
            "description": "Improve flexibility and range of motion in your knee",
            "target_joints": "knee,ankle",
            "instructions": "Sit on a chair with feet flat on the floor;Slowly slide one foot back, bending your knee;Hold for 5 seconds;Return to starting position;Repeat 10 times, then switch legs"
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Straight Leg Raises",
            "description": "Strengthen the quadriceps without stressing the knee joint",
            "target_joints": "hip,knee",
            "instructions": "Lie on your back with one leg bent and one leg straight;Tighten the thigh muscles of your straight leg;Lift the straight leg up about 12 inches;Hold for 5 seconds, then slowly lower;Repeat 10 times, then switch legs"
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Step-Ups",
            "description": "Strengthen your knee by stepping up and down a step",
            "target_joints": "knee,hip,ankle",
            "instructions": "Stand in front of a step or sturdy platform;Step up with your affected leg;Bring your other foot up to join it;Step down with the affected leg first;Repeat 10 times, then switch legs"
        }
    ]
    
    for exercise in exercises:
        cursor.execute('''
        INSERT OR IGNORE INTO exercises (id, name, description, target_joints, instructions)
        VALUES (?, ?, ?, ?, ?)
        ''', (
            exercise["id"],
            exercise["name"],
            exercise["description"],
            exercise["target_joints"],
            exercise["instructions"]
        ))
    
    conn.commit()
    conn.close()

# Initialize database and sample data
init_db()
populate_sample_exercises()

@app.route('/api/process_audio', methods=['POST'])
def process_audio():
    """Process audio file and extract patient information and pain points"""
    if 'audio' not in request.files:
        return jsonify({"error": "No audio file provided"}), 400
    
    audio_file = request.files['audio']
    patient_id = request.form.get('patient_id')
    
    # Save audio file to GCP bucket
    filename = f"{uuid.uuid4()}.wav"
    blob = storage_client.bucket(BUCKET_NAME).blob(f"audio/{filename}")
    blob.upload_from_file(audio_file)
    
    # Transcribe audio with Google Speech-to-Text
    audio_uri = f"gs://{BUCKET_NAME}/audio/{filename}"
    audio = speech.RecognitionAudio(uri=audio_uri)
    config = speech.RecognitionConfig(
        encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
        sample_rate_hertz=16000,
        language_code="en-US",
    )
    
    response = speech_client.recognize(config=config, audio=audio)
    
    # Extract text from transcription
    transcription = ""
    for result in response.results:
        transcription += result.alternatives[0].transcript
    
    # Process transcription to extract information
    # In a real system, you'd use NLP to extract structured data
    # Here we'll use simple keyword matching for demonstration
    words = word_tokenize(transcription.lower())
    stop_words = set(stopwords.words('english'))
    keywords = [word for word in words if word not in stop_words]
    
    # Extract name if present
    name = ""
    name_indicators = ["name is", "i am", "call me", "i'm"]
    for indicator in name_indicators:
        if indicator in transcription.lower():
            parts = transcription.lower().split(indicator)
            if len(parts) > 1:
                potential_name = parts[1].strip().split()[0]
                if potential_name and potential_name not in stop_words:
                    name = potential_name.capitalize()
                    break
    
    # Extract pain points
    pain_keywords = ["pain", "hurt", "sore", "ache", "stiff", "swelling", "weak"]
    location_keywords = ["knee", "joint", "leg", "thigh", "calf", "ankle", "hip"]
    activity_keywords = ["walking", "stairs", "running", "jumping", "sitting", "standing"]
    
    pain_points = []
    for pain in pain_keywords:
        if pain in keywords:
            idx = keywords.index(pain)
            # Look for locations and activities near the pain keyword
            nearby_words = keywords[max(0, idx-5):idx+5]
            
            locations = [loc for loc in location_keywords if loc in nearby_words]
            activities = [act for act in activity_keywords if act in nearby_words]
            
            if locations or activities:
                pain_point = {
                    "type": pain,
                    "locations": locations,
                    "activities": activities,
                    "severity": 5  # Default mid-level severity
                }
                pain_points.append(pain_point)
    
    # Store patient info in database if it's a new patient
    if not patient_id:
        patient_id = str(uuid.uuid4())
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        now = datetime.datetime.now().isoformat()
        
        cursor.execute('''
        INSERT INTO patients (id, name, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        ''', (patient_id, name, now, now))
        
        # Store pain points
        for pain in pain_points:
            pain_id = str(uuid.uuid4())
            description = f"{pain['type']} in {', '.join(pain['locations'])} during {', '.join(pain['activities'])}"
            
            cursor.execute('''
            INSERT INTO pain_points (id, patient_id, description, severity, created_at)
            VALUES (?, ?, ?, ?, ?)
            ''', (pain_id, patient_id, description, pain['severity'], now))
        
        conn.commit()
        conn.close()
    
    # Recommend exercises based on pain points
    recommended_exercises = recommend_exercises(pain_points)
    
    # Store exercise recommendations
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    now = datetime.datetime.now().isoformat()
    
    for exercise in recommended_exercises:
        cursor.execute('''
        INSERT INTO patient_exercises (id, patient_id, exercise_id, recommended_at)
        VALUES (?, ?, ?, ?)
        ''', (str(uuid.uuid4()), patient_id, exercise["id"], now))
    
    conn.commit()
    conn.close()
    
    # Return response with recommendations
    return jsonify({
        "patient_id": patient_id,
        "name": name,
        "transcription": transcription,
        "pain_points": pain_points,
        "recommended_exercises": recommended_exercises
    })

def recommend_exercises(pain_points):
    """Recommend exercises based on detected pain points"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Get all exercises
    cursor.execute('SELECT id, name, description, target_joints, instructions FROM exercises')
    exercises = cursor.fetchall()
    
    recommended = []
    
    # Extract all unique locations from pain points
    locations = set()
    activities = set()
    
    for pain in pain_points:
        locations.update(pain.get("locations", []))
        activities.update(pain.get("activities", []))
    
    # Simple matching logic
    # In a real system, you'd have a more sophisticated recommendation engine
    for exercise_data in exercises:
        ex_id, name, description, target_joints, instructions = exercise_data
        
        # Convert target joints to a list
        joints = target_joints.split(",")
        instructions_list = instructions.split(";")
        
        # Check if exercise targets affected locations
        for location in locations:
            if location in joints or location in description.lower():
                recommended.append({
                    "id": ex_id,
                    "name": name,
                    "description": description,
                    "target_joints": joints,
                    "instructions": instructions_list
                })
                break
    
    # If no exercises match the pain points, recommend general exercises
    if not recommended:
        # Get a general knee exercise
        cursor.execute('SELECT id, name, description, target_joints, instructions FROM exercises LIMIT 1')
        exercise_data = cursor.fetchone()
        
        if exercise_data:
            ex_id, name, description, target_joints, instructions = exercise_data
            recommended.append({
                "id": ex_id,
                "name": name,
                "description": description,
                "target_joints": target_joints.split(","),
                "instructions": instructions.split(";")
            })
    
    conn.close()
    return recommended

@app.route('/api/log_exercise', methods=['POST'])
def log_exercise():
    """Log a completed exercise session"""
    data = request.json
    
    patient_id = data.get('patient_id')
    exercise_id = data.get('exercise_id')
    duration = data.get('duration')
    completed = data.get('completed', True)
    notes = data.get('notes', '')
    
    if not patient_id or not exercise_id:
        return jsonify({"error": "Patient ID and Exercise ID are required"}), 400
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    now = datetime.datetime.now().isoformat()
    session_id = str(uuid.uuid4())
    
    cursor.execute('''
    INSERT INTO exercise_sessions (id, patient_id, exercise_id, duration, completed, notes, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (session_id, patient_id, exercise_id, duration, completed, notes, now))
    
    conn.commit()
    conn.close()
    
    return jsonify({
        "success": True,
        "session_id": session_id
    })

@app.route('/api/patient_report/<patient_id>', methods=['GET'])
def patient_report(patient_id):
    """Generate a report of patient's exercises and progress"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    # Get patient info
    cursor.execute('SELECT * FROM patients WHERE id = ?', (patient_id,))
    patient = cursor.fetchone()
    
    if not patient:
        return jsonify({"error": "Patient not found"}), 404
    
    # Get pain points
    cursor.execute('SELECT * FROM pain_points WHERE patient_id = ?', (patient_id,))
    pain_points = [dict(row) for row in cursor.fetchall()]
    
    # Get recommended exercises
    cursor.execute('''
    SELECT e.*, pe.recommended_at 
    FROM exercises e
    JOIN patient_exercises pe ON e.id = pe.exercise_id
    WHERE pe.patient_id = ?
    ''', (patient_id,))
    recommendations = [dict(row) for row in cursor.fetchall()]
    
    # Get exercise sessions
    cursor.execute('''
    SELECT es.*, e.name as exercise_name
    FROM exercise_sessions es
    JOIN exercises e ON es.exercise_id = e.id
    WHERE es.patient_id = ?
    ORDER BY es.created_at DESC
    ''', (patient_id,))
    sessions = [dict(row) for row in cursor.fetchall()]
    
    # Calculate progress metrics
    total_sessions = len(sessions)
    completed_sessions = sum(1 for s in sessions if s['completed'])
    total_duration = sum(s['duration'] for s in sessions if s['duration'])
    
    # Calculate adherence percentage
    adherence = (completed_sessions / total_sessions * 100) if total_sessions > 0 else 0
    
    conn.close()
    
    return jsonify({
        "patient": dict(patient),
        "pain_points": pain_points,
        "recommendations": recommendations,
        "sessions": sessions,
        "metrics": {
            "total_sessions": total_sessions,
            "completed_sessions": completed_sessions,
            "total_duration_minutes": total_duration,
            "adherence_percentage": adherence
        }
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))