import SwiftUI

struct ExerciseCard: View {
    let exercise: Exercise
    let onAddNewExercise: () -> Void
    
    var body: some View {
        HStack {
            // Exercise image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                if let imageURL = exercise.imageURL1 {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "figure.walk")
                                .font(.system(size: 30))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                } else {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 30))
                }
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                
                Text(exercise.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: "clock")
                    Text("\(Int(exercise.duration / 60)) min")
                    
                    Spacer()
                    
                    Image(systemName: "figure.walk")
                    Text("\(exercise.targetJoints.count) targets")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 8)
    }
}

struct AddExerciseCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Custom Exercise")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    Text("Add your own custom exercise")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Text("Tap to add using voice or text")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                }
                .padding(.leading, 8)
            }
            .padding(.vertical, 8)
        }
    }
}

struct ExerciseListView: View {
    @State private var exercises = Exercise.examples
    @State private var showingPermissionsAlert = false
    @State private var showingAddExerciseSheet = false
    @State private var exerciseVoiceInput = ""
    
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    @EnvironmentObject private var voiceManager: VoiceManager
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    
    var body: some View {
        NavigationView {
            List {
                // Add Exercise section available to all users
                Section(header: Text("Add Your Own Exercise").font(.headline)) {
                    AddExerciseCard(onTap: {
                        showAddExerciseSheet()
                    })
                }
                
                if !exercises.isEmpty {
                    Section(header: Text("Your Exercises").font(.headline)) {
                        ForEach(exercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                ExerciseCard(
                                    exercise: exercise,
                                    onAddNewExercise: {
                                        showAddExerciseSheet()
                                    }
                                )
                            }
                        }
                    }
                } else {
                    Text("No exercises available. Complete the onboarding to get recommendations.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Knee Recovery Exercises")
            .navigationBarItems(
                leading: ResetOnboardingButton()
            )
            .alert(isPresented: $showingPermissionsAlert) {
                Alert(
                    title: Text("Permissions Required"),
                    message: Text("This app requires camera and microphone permissions for exercises."),
                    primaryButton: .default(Text("Settings"), action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }),
                    secondaryButton: .cancel()
                )
            }
            .sheet(isPresented: $showingAddExerciseSheet) {
                AddExerciseView(onExerciseAdded: { exerciseName, voiceInstructions in
                    // Make a real API call to add the exercise
                    addCustomExercise(name: exerciseName, voiceInstructions: voiceInstructions)
                })
            }
            .onAppear {
                // Refresh exercises from the stored list
                exercises = Exercise.examples
                
                // End any ongoing voice session
                voiceManager.endElevenLabsSession()
                
                // Optional: Check if permissions are already granted
                resourceCoordinator.checkInitialPermissions()
            }
        }
    }
    
    private func showAddExerciseSheet() {
        speechRecognitionManager.recognizedText = ""
        showingAddExerciseSheet = true
    }
    
    private func checkPermissions() {
        resourceCoordinator.checkAllPermissions { allGranted in
            if !allGranted {
                showingPermissionsAlert = true
            }
        }
    }
    
    private func addCustomExercise(name: String, voiceInstructions: String = "") {
        // Show loading indicator
        var isAddingExercise = true
        var addExerciseError: String? = nil
        
        // Construct the request body
        let requestBody: [String: Any] = [
            "action": "add",
            "user_id": UserDefaults.standard.string(forKey: "user_id") ?? UUID().uuidString,
            "patient_id": UserDefaults.standard.string(forKey: "patient_id") ?? UUID().uuidString,
            "exercise_name": name,
            "llm_provider": "openai", // Default to openai, could be made configurable
            "voice_instructions": voiceInstructions
        ]
        
        // Convert request body to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            // If this fails, fall back to local placeholder creation
            addLocalPlaceholderExercise(name: name)
            return
        }
        
        // Create the URL request
        let urlString = "https://us-central1-duoligo-pt-app.cloudfunctions.net/manage_exercise"
        guard let url = URL(string: urlString) else {
            // If this fails, fall back to local placeholder creation
            addLocalPlaceholderExercise(name: name)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Create the data task
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isAddingExercise = false
                
                if let error = error {
                    print("Error adding exercise: \(error.localizedDescription)")
                    // Fall back to local placeholder
                    self.addLocalPlaceholderExercise(name: name)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid response from server")
                    // Fall back to local placeholder
                    self.addLocalPlaceholderExercise(name: name)
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    print("Server error: HTTP \(httpResponse.statusCode)")
                    // Fall back to local placeholder
                    self.addLocalPlaceholderExercise(name: name)
                    return
                }
                
                guard let data = data else {
                    print("No data received from server")
                    // Fall back to local placeholder
                    self.addLocalPlaceholderExercise(name: name)
                    return
                }
                
                // Parse the response
                do {
                    let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let status = responseDict?["status"] as? String, status == "success" {
                        // Handle success - add the new exercise to the list
                        if let exerciseData = responseDict?["exercise"] as? [String: Any] {
                            // Create a new Exercise object from the response
                            let id = UUID(uuidString: exerciseData["id"] as? String ?? "") ?? UUID()
                            let name = exerciseData["name"] as? String ?? "Custom Exercise"
                            let description = exerciseData["description"] as? String ?? ""
                            let videoUrl = exerciseData["video_url"] as? String
                            
                            // Convert target_joints array to BodyJointType array
                            var targetJoints: [BodyJointType] = []
                            if let joints = exerciseData["target_joints"] as? [String] {
                                for joint in joints {
                                    if let bodyJoint = BodyJointType(rawValue: joint) {
                                        targetJoints.append(bodyJoint)
                                    }
                                }
                            }
                            
                            // Convert instructions array to [String]
                            var instructions: [String] = []
                            if let instructionsList = exerciseData["instructions"] as? [String] {
                                instructions = instructionsList
                            }
                            
                            let newExercise = Exercise(
                                id: id,
                                name: name,
                                description: description,
                                imageURLString: videoUrl,
                                duration: 180, // Default duration
                                targetJoints: targetJoints,
                                instructions: instructions
                            )
                            
                            // Add to exercises list
                            self.exercises.append(newExercise)
                        } else {
                            // If response is missing exercise data, fall back to local placeholder
                            self.addLocalPlaceholderExercise(name: name)
                        }
                    } else {
                        // If response status is not success, fall back to local placeholder
                        self.addLocalPlaceholderExercise(name: name)
                    }
                } catch {
                    print("Failed to parse response: \(error.localizedDescription)")
                    // Fall back to local placeholder
                    self.addLocalPlaceholderExercise(name: name)
                }
            }
        }
        
        // Start the request
        task.resume()
    }
    
    // Fallback method to add a placeholder exercise locally when API call fails
    private func addLocalPlaceholderExercise(name: String) {
        let newExercise = Exercise(
            id: UUID(),
            name: name,
            description: "Custom exercise added by you",
            imageURLString: nil,
            duration: 180,
            targetJoints: [Joint.leftKnee, Joint.rightKnee],
            instructions: [
                "This exercise will be customized by you",
                "Add your own instructions in the exercise details"
            ]
        )
        
        exercises.append(newExercise)
    }
}

// Updated view for adding a new exercise via voice
struct AddExerciseView: View {
    let onExerciseAdded: (String, String) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var exerciseName = ""
    @State private var exerciseInstructions = ""
    @State private var isRecordingVoice = false
    @State private var isRecordingInstructions = false
    
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Add a New Exercise")
                        .font(.title)
                        .padding(.top, 30)
                    
                    // Exercise Name Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exercise Name")
                            .font(.headline)
                        
                        Text("Specify the exercise name using your voice or by typing")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g. Single-Leg Balance", text: $exerciseName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.vertical, 8)
                        
                        // Voice input button for name
                        Button(action: {
                            toggleVoiceRecording(forInstructions: false)
                        }) {
                            HStack {
                                Image(systemName: isRecordingVoice && !isRecordingInstructions ? "mic.fill" : "mic")
                                    .foregroundColor(isRecordingVoice && !isRecordingInstructions ? .red : .blue)
                                Text(isRecordingVoice && !isRecordingInstructions ? "Stop Recording" : "Record Exercise Name")
                            }
                            .padding(8)
                            .background(isRecordingVoice && !isRecordingInstructions ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if isRecordingVoice && !isRecordingInstructions {
                            Text(speechRecognitionManager.recognizedText)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Exercise Instructions Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exercise Instructions (Optional)")
                            .font(.headline)
                        
                        Text("Describe how to perform this exercise")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            if exerciseInstructions.isEmpty {
                                Text("e.g. Stand on one leg with your knee slightly bent...")
                                    .foregroundColor(.gray)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            
                            TextEditor(text: $exerciseInstructions)
                                .frame(minHeight: 100)
                                .padding(4)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        .frame(minHeight: 100)
                        
                        // Voice input button for instructions
                        Button(action: {
                            toggleVoiceRecording(forInstructions: true)
                        }) {
                            HStack {
                                Image(systemName: isRecordingInstructions ? "mic.fill" : "mic")
                                    .foregroundColor(isRecordingInstructions ? .red : .blue)
                                Text(isRecordingInstructions ? "Stop Recording" : "Record Instructions")
                            }
                            .padding(8)
                            .background(isRecordingInstructions ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if isRecordingInstructions {
                            Text(speechRecognitionManager.recognizedText)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Add button
                    Button(action: {
                        if !exerciseName.isEmpty {
                            onExerciseAdded(exerciseName, exerciseInstructions)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        Text("Add Exercise")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(!exerciseName.isEmpty ? Color.blue : Color.gray)
                            .cornerRadius(10)
                    }
                    .disabled(exerciseName.isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .onChange(of: speechRecognitionManager.recognizedText) { newValue in
                if !newValue.isEmpty {
                    if isRecordingInstructions {
                        exerciseInstructions = newValue
                    } else if isRecordingVoice {
                        exerciseName = newValue
                    }
                }
            }
        }
    }
    
    private func toggleVoiceRecording(forInstructions: Bool) {
        // Stop any ongoing recording first
        if isRecordingVoice || isRecordingInstructions {
            speechRecognitionManager.stopListening()
            isRecordingVoice = false
            isRecordingInstructions = false
        } else {
            // Start new recording
            speechRecognitionManager.recognizedText = ""
            speechRecognitionManager.startListening()
            
            if forInstructions {
                isRecordingInstructions = true
            } else {
                isRecordingVoice = true
            }
        }
    }
}

