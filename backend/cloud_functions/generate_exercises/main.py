import functions_framework
import json
import uuid
import os
import requests
import re
import logging
from google.cloud import firestore
from google.cloud import secretmanager
from datetime import datetime

# Set up logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('generate_exercises')

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
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{os.environ['PROJECT_ID']}/secrets/{secret_id}/versions/{version_id}"
        response = client.access_secret_version(request={"name": name})
        # Strip whitespace and newlines to avoid issues with API keys
        return response.payload.data.decode("UTF-8").strip()
    except Exception as e:
        logger.error(f"Error accessing secret '{secret_id}': {str(e)}")
        raise

# Initialize Firestore DB (default)
db = firestore.Client()

# Function to get API keys from Secret Manager
def get_api_keys():
    """
    Get all required API keys from Secret Manager
    """
    keys = {
        'google_api_key': access_secret_version("google-api-key"),
        'google_cse_id': access_secret_version("google-cse-id"),
        'anthropic_api_key': access_secret_version("anthropic-api-key"),
        'openai_api_key': access_secret_version("openai-api-key")
    }
    
    # Verify we have the required keys
    if not keys['google_api_key'] or not keys['google_cse_id']:
        logger.error("Missing required Google API keys")
        raise ValueError("Missing required Google API keys. Please check Secret Manager.")
    
    return keys

@functions_framework.http
def generate_exercises(request):
    """
    Cloud Function to generate exercises for a patient using LLM and
    add real video URLs using Google Custom Search API.
    
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
        
        logger.info(f"Processing request for patient_id: {patient_id}, llm_provider: {llm_provider}")
        
        # Get all API keys from Secret Manager once at the beginning
        api_keys = get_api_keys()
        
        # 1. First, check if suitable exercises already exist in the database
        existing_exercises = check_existing_exercises(patient_id)
        
        if existing_exercises and len(existing_exercises) >= 3:
            logger.info(f"Found {len(existing_exercises)} existing exercises for patient")
            
            # Debug: Validate existing video links
            for exercise in existing_exercises:
                video_url = exercise.get('video_url', '')
                if video_url:
                    logger.info(f"Existing exercise '{exercise['name']}' has video URL: {video_url}")
                    validate_video_url(video_url, exercise['name'])
            
            # Make sure existing exercises have video thumbnails
            for exercise in existing_exercises:
                if not exercise.get('video_thumbnail') and exercise.get('video_url'):
                    exercise['video_thumbnail'] = get_video_thumbnail(exercise['video_url'])
            
            return (json.dumps({
                'status': 'success', 
                'exercises': existing_exercises,
                'source': 'database'
            }, cls=DateTimeEncoder), 200, headers)
        
        # 2. If not enough existing exercises, get patient data
        patient_data = get_patient_data(patient_id)
        if not patient_data:
            logger.warning(f"Patient not found: {patient_id}")
            return (json.dumps({'error': 'Patient not found'}, cls=DateTimeEncoder), 404, headers)
        
        # 3. Generate exercises using LLM (without video URLs)
        if llm_provider == 'openai':
            exercises = generate_exercises_with_openai(patient_data, api_keys['openai_api_key'])
        else:  # Default to Claude
            exercises = generate_exercises_with_claude(patient_data, api_keys['anthropic_api_key'])
        
        logger.info(f"Generated {len(exercises)} exercises using {llm_provider}")
        
        # 4. Enhance exercises with real video URLs and thumbnails
        enhanced_exercises = enhance_exercises_with_videos(exercises, api_keys['google_api_key'], api_keys['google_cse_id'])
        
        # 5. Save the generated exercises to Firestore
        saved_exercises = save_exercises(enhanced_exercises, patient_id)
        
        # 6. Return the exercises
        return (json.dumps({
            'status': 'success',
            'exercises': saved_exercises,
            'source': 'llm-generated'
        }, cls=DateTimeEncoder), 200, headers)
        
    except Exception as e:
        logger.error(f"Error generating exercises: {str(e)}", exc_info=True)
        return (json.dumps({'error': f'Error generating exercises: {str(e)}'}, cls=DateTimeEncoder), 500, headers)


def validate_video_url(url, exercise_name):
    """
    Check if a YouTube video URL is still valid
    """
    try:
        if 'youtube.com' in url or 'youtu.be' in url:
            # Extract video ID
            video_id = None
            if 'youtube.com/watch?v=' in url:
                video_id = url.split('youtube.com/watch?v=')[1].split('&')[0]
            elif 'youtu.be/' in url:
                video_id = url.split('youtu.be/')[1].split('?')[0]
            
            if not video_id:
                logger.warning(f"Could not extract video ID from URL: {url}")
                return False
                
            # Check video info via oEmbed API (lightweight way to validate)
            oembed_url = f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={video_id}&format=json"
            response = requests.get(oembed_url)
            
            if response.status_code == 200:
                logger.info(f"✅ Video for '{exercise_name}' is valid: {url}")
                return True
            else:
                logger.warning(f"❌ Video for '{exercise_name}' may be unavailable: {url}")
                return False
    except Exception as e:
        logger.warning(f"Error validating video URL {url}: {str(e)}")
    
    return False


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


def generate_exercises_with_claude(patient_data, api_key):
    """
    Generate exercises using Anthropic's Claude API
    (Modified to request exercises without video URLs)
    """
    try:
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
        
        DO NOT include video URLs or links. I will add them separately.
        
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
            ]
          }}
        ]
        ```
        
        Respond ONLY with the JSON array and nothing else.
        """
        
        logger.info("Calling Claude API to generate exercises")
        
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
            logger.error(f"Claude API error: {response.text}")
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
        logger.info(f"Claude generated {len(exercises)} exercises")
        
        return exercises
    except Exception as e:
        logger.error(f"Error in generate_exercises_with_claude: {str(e)}", exc_info=True)
        raise Exception(f"Error in generate_exercises_with_claude: {str(e)}")


def generate_exercises_with_openai(patient_data, api_key):
    """
    Generate exercises using OpenAI's GPT API
    (Modified to request exercises without video URLs)
    """
    try:
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
        
        DO NOT include video URLs or links. I will add them separately.
        
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
            ]
          }}
        ]
        
        Respond ONLY with the JSON array and nothing else.
        """
        
        logger.info("Calling OpenAI API to generate exercises")
        
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
            logger.error(f"OpenAI API error: {response.text}")
            raise Exception(f"OpenAI API error: {response.text}")
        
        result = response.json()
        content = result.get('choices', [{}])[0].get('message', {}).get('content', '[]')
        
        exercises = json.loads(content)
        logger.info(f"OpenAI generated {len(exercises)} exercises")
        
        return exercises
    except Exception as e:
        logger.error(f"Error in generate_exercises_with_openai: {str(e)}", exc_info=True)
        raise Exception(f"Error in generate_exercises_with_openai: {str(e)}")


def enhance_exercises_with_videos(exercises, google_api_key, google_cse_id):
    """
    Add real video URLs and thumbnails to exercises using Google Custom Search API
    """
    enhanced_exercises = []
    
    for exercise in exercises:
        # Create search query for exercise videos
        search_query = f"{exercise['name']} physical therapy exercise"
        logger.info(f"Searching for videos: '{search_query}'")
        
        video_data = search_youtube_video(search_query, google_api_key, google_cse_id)
        
        # Add video data to exercise
        exercise_with_video = exercise.copy()
        
        if video_data:
            exercise_with_video['video_url'] = video_data.get('video_url', '')
            exercise_with_video['video_thumbnail'] = video_data.get('thumbnail', '')
            
            # Validate the found video
            is_valid = validate_video_url(exercise_with_video['video_url'], exercise['name'])
            if not is_valid:
                # Try a more specific search if the first result isn't valid
                logger.info(f"First video result for '{exercise['name']}' was invalid, trying alternative search...")
                alt_search_query = f"{exercise['name']} knee rehabilitation exercise demonstration"
                alt_video_data = search_youtube_video(alt_search_query, google_api_key, google_cse_id, num_results=5)
                
                if alt_video_data:
                    exercise_with_video['video_url'] = alt_video_data.get('video_url', '')
                    exercise_with_video['video_thumbnail'] = alt_video_data.get('thumbnail', '')
                    logger.info(f"Alternative search found video: {exercise_with_video['video_url']}")
                    validate_video_url(exercise_with_video['video_url'], exercise['name'])
        else:
            # Fallback if no video found
            logger.warning(f"❌ No video found for '{exercise['name']}'")
            exercise_with_video['video_url'] = ''
            exercise_with_video['video_thumbnail'] = ''
        
        enhanced_exercises.append(exercise_with_video)
    
    return enhanced_exercises


def search_youtube_video(query, google_api_key, google_cse_id, num_results=1):
    """
    Search for YouTube videos using Google Custom Search API and return the URL and thumbnail
    of the most relevant video.
    """
    try:
        # Build the API request
        url = "https://www.googleapis.com/customsearch/v1"
        params = {
            'key': google_api_key,
            'cx': google_cse_id,
            'q': query + " youtube", # Add youtube to focus on YouTube results
            'num': num_results  # Number of results to return
        }
        
        logger.info(f"Calling Google Custom Search API with query: '{query} youtube'")
        logger.info(f"API URL: {url}")
        logger.info(f"API params: cx={google_cse_id}, num={num_results}")
        
        # Make the API request
        response = requests.get(url, params=params)
        
        # Log the response status and headers
        logger.info(f"API response status: {response.status_code}")
        logger.info(f"API response headers: {response.headers}")
        
        # Check for errors
        if response.status_code != 200:
            logger.error(f"Google Search API error: {response.text}")
            return None
        
        # Process the response
        data = response.json()
        
        # Log the full response structure for debugging
        logger.info(f"API response keys: {list(data.keys())}")
        
        if 'searchInformation' in data:
            logger.info(f"Search info: {data['searchInformation']}")
        
        # Check if we got search results
        if 'items' not in data or len(data['items']) == 0:
            logger.warning("No search results found")
            if 'error' in data:
                logger.error(f"API returned error: {data['error']}")
            return None
        
        # Log the number of results
        logger.info(f"Found {len(data['items'])} search results")
        
        # Get all video results
        all_videos = []
        for idx, item in enumerate(data['items']):
            # Log the structure of each result
            logger.info(f"Result {idx+1} keys: {list(item.keys())}")
            
            video_url = item.get('link', '')
            logger.info(f"Result {idx+1} link: {video_url}")
            
            # Check if this is a YouTube link
            is_youtube = 'youtube.com' in video_url or 'youtu.be' in video_url
            logger.info(f"Result {idx+1} is YouTube: {is_youtube}")
            
            # Only process YouTube links
            if not is_youtube:
                logger.info(f"Skipping non-YouTube result: {video_url}")
                continue
                
            # Get thumbnail image if available
            thumbnail = ''
            if 'pagemap' in item:
                logger.info(f"Result {idx+1} pagemap keys: {list(item['pagemap'].keys())}")
                
                if 'cse_image' in item['pagemap']:
                    thumbnail = item['pagemap']['cse_image'][0].get('src', '')
                    logger.info(f"Found thumbnail in cse_image: {thumbnail}")
                elif 'videoobject' in item['pagemap']:
                    thumbnail = item['pagemap']['videoobject'][0].get('thumbnailurl', '')
                    logger.info(f"Found thumbnail in videoobject: {thumbnail}")
            else:
                logger.warning(f"Result {idx+1} has no pagemap")
            
            # If no thumbnail found, generate one from YouTube video ID
            if not thumbnail and is_youtube:
                video_id = None
                if 'youtube.com/watch?v=' in video_url:
                    video_id = video_url.split('youtube.com/watch?v=')[1].split('&')[0]
                elif 'youtu.be/' in video_url:
                    video_id = video_url.split('youtu.be/')[1].split('?')[0]
                
                if video_id:
                    thumbnail = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
                    logger.info(f"Generated thumbnail from video ID: {thumbnail}")
            
            logger.info(f"Final result {idx+1}: URL={video_url}, Thumbnail={thumbnail}")
            
            all_videos.append({
                'title': item.get('title', 'Unknown'),
                'video_url': video_url,
                'thumbnail': thumbnail
            })
        
        # If we have YouTube results
        if all_videos:
            logger.info(f"Found {len(all_videos)} YouTube videos")
            # Return the first result
            result = all_videos[0]
            logger.info(f"Returning video: {result['video_url']}")
            logger.info(f"With thumbnail: {result['thumbnail']}")
            return result
        else:
            logger.warning("No YouTube videos found in search results")
            return None
            
    except Exception as e:
        logger.error(f"Error searching for video: {str(e)}", exc_info=True)
        return None


def get_video_thumbnail(video_url):
    """
    Extract or generate a thumbnail URL from a video URL if possible.
    This is a fallback for existing exercises that may not have thumbnails.
    """
    # For YouTube videos
    if 'youtube.com' in video_url or 'youtu.be' in video_url:
        # Extract YouTube video ID
        video_id = None
        if 'youtube.com/watch?v=' in video_url:
            video_id = video_url.split('youtube.com/watch?v=')[1].split('&')[0]
        elif 'youtu.be/' in video_url:
            video_id = video_url.split('youtu.be/')[1].split('?')[0]
        
        if video_id:
            thumbnail_url = f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            logger.info(f"Generated thumbnail URL: {thumbnail_url}")
            return thumbnail_url
    
    # Default empty if we can't determine the thumbnail
    return ""


def save_exercises(exercises, patient_id):
    """
    Save generated exercises to Firestore and link them to the patient
    """
    saved_exercises = []
    
    for exercise in exercises:
        # Log the video URL we're saving
        logger.info(f"Saving exercise '{exercise['name']}' with video URL: {exercise.get('video_url', 'None')}")
        
        # Check if a similar exercise already exists
        similar_exercises = db.collection('exercises').where('name', '==', exercise['name']).limit(1).get()
        
        if len(similar_exercises) > 0:
            # Use existing exercise
            exercise_id = similar_exercises[0].id
            exercise_data = similar_exercises[0].to_dict()
            
            # Update with video URL and thumbnail if they were missing
            if (not exercise_data.get('video_url') and exercise.get('video_url')) or \
               (not exercise_data.get('video_thumbnail') and exercise.get('video_thumbnail')):
                updates = {}
                if not exercise_data.get('video_url') and exercise.get('video_url'):
                    updates['video_url'] = exercise['video_url']
                if not exercise_data.get('video_thumbnail') and exercise.get('video_thumbnail'):
                    updates['video_thumbnail'] = exercise['video_thumbnail']
                
                if updates:
                    db.collection('exercises').document(exercise_id).update(updates)
                    exercise_data.update(updates)
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
                'video_thumbnail': exercise.get('video_thumbnail', ''),
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