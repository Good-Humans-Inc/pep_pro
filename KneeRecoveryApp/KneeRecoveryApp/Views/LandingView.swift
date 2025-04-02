import SwiftUI

// Define Joint enum to replace BodyJointType for this view
enum Joint: String, CaseIterable {
    case leftKnee = "left_knee"
    case rightKnee = "right_knee"
    case leftAnkle = "left_ankle"
    case rightAnkle = "right_ankle"
    case leftHip = "left_hip"
    case rightHip = "right_hip"
}

// MARK: - AddExerciseSheet View Modifier
struct AddExerciseSheetModifier: ViewModifier {
    @Binding var exercises: [Exercise]
    @State private var showingAddExerciseSheet = false
    
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddExerciseSheet) {
                AddExerciseView(onExerciseAdded: { exerciseName, voiceInstructions in
                    addCustomExercise(name: exerciseName, voiceInstructions: voiceInstructions)
                })
            }
            .environment(\.showAddExerciseSheetAction, {
                speechRecognitionManager.recognizedText = ""
                showingAddExerciseSheet = true
            })
    }
    
    private func addCustomExercise(name: String, voiceInstructions: String = "") {
        // Create a new exercise locally
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
        
        // Add it to the exercises array
        exercises.append(newExercise)
        
        // Call API to add custom exercise
        guard let patientId = UserDefaults.standard.string(forKey: "PatientID") else { return }
        
        let url = URL(string: "https://us-central1-pep-pro.cloudfunctions.net/add_custom_exercise")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "pt_id": "pt-uuid", // Replace with actual PT ID
            "patient_id": patientId,
            "exercise_name": name,
            "llm_provider": "openai",
            "voice_instructions": voiceInstructions
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error adding custom exercise: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received from add exercise API")
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("Successfully added custom exercise: \(json ?? [:])")
            } catch {
                print("Error parsing add exercise response: \(error)")
            }
        }.resume()
    }
}

// MARK: - Environment Key for Show Sheet Action
private struct ShowAddExerciseSheetKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

extension EnvironmentValues {
    var showAddExerciseSheetAction: () -> Void {
        get { self[ShowAddExerciseSheetKey.self] }
        set { self[ShowAddExerciseSheetKey.self] = newValue }
    }
}

// MARK: - View Extension for Modifier
extension View {
    func withAddExerciseSheet(exercises: Binding<[Exercise]>) -> some View {
        modifier(AddExerciseSheetModifier(exercises: exercises))
    }
    
    func showAddExerciseSheet() {
        @Environment(\.showAddExerciseSheetAction) var showSheet
        showSheet()
    }
}

// Separate view for exercise item to break up complex view hierarchy
struct ExerciseItemView: View {
    let exercise: Exercise
    
    // Environment objects
    @EnvironmentObject var resourceCoordinator: ResourceCoordinator
    @EnvironmentObject var voiceManager: VoiceManager
    @EnvironmentObject var speechRecognitionManager: SpeechRecognitionManager
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var visionManager: VisionManager
    
    var onAddNewExercise: () -> Void
    
    var body: some View {
        NavigationLink {
            // Destination view
            ExerciseDetailView(exercise: exercise)
                .environmentObject(resourceCoordinator)
                .environmentObject(voiceManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(cameraManager)
                .environmentObject(visionManager)
                .id(exercise.id.uuidString)
        } label: {
            // Label view
            ExerciseCard(
                exercise: exercise,
                onAddNewExercise: onAddNewExercise
            )
        }
    }
}

// Loading View for exercises
struct LoadingExercisesView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView("Loading exercises...")
            Spacer()
        }
        .padding()
    }
}

// Empty Exercises View
struct EmptyExercisesView: View {
    var body: some View {
        Text("No exercises available. Complete the onboarding to get recommendations.")
            .font(.body)
            .foregroundColor(.secondary)
            .padding()
    }
}

// MARK: - LandingView is the list of exercises
struct LandingView: View {
    @State private var exercises = [Exercise]()
    @State private var showingPermissionsAlert = false
    @State private var isLoadingExercises = false
    
    // Environment objects
    @EnvironmentObject var resourceCoordinator: ResourceCoordinator
    @EnvironmentObject var voiceManager: VoiceManager
    @EnvironmentObject var speechRecognitionManager: SpeechRecognitionManager
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var visionManager: VisionManager
    
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Knee Recovery Exercises")
                .navigationBarItems(
                    leading: ResetOnboardingButton(),
                    trailing: Button(action: {
                        checkPermissions()
                    }) {
                        Image(systemName: "info.circle")
                    }
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
                .onAppear {
                    // Load exercises from the API or local storage
                    loadExercises()
                    
                    // End any ongoing voice session
                    if voiceManager.isSessionActive {
                        print("⚠️ Unexpected active voice session in LandingView - ending it")
                        voiceManager.endElevenLabsSession()
                    }
                    
                    // Optional: Check if permissions are already granted
                    resourceCoordinator.checkInitialPermissions()
                }
        }
        // Apply the custom modifier to handle add exercise sheet
        .withAddExerciseSheet(exercises: $exercises)
    }
    
    // Breaking the content into a separate computed property
    private var contentView: some View {
        List {
            if isLoadingExercises {
                LoadingExercisesView()
            } else if !exercises.isEmpty {
                exercisesSection
            } else {
                EmptyExercisesView()
            }
        }
    }
    
    // Breaking the exercises section into a separate computed property
    private var exercisesSection: some View {
        Section(header: Text("Your Recommended Exercises").font(.headline)) {
            ForEach(exercises) { exercise in
                ExerciseItemView(
                    exercise: exercise,
                    onAddNewExercise: { showAddExerciseSheet() }
                )
                .environmentObject(resourceCoordinator)
                .environmentObject(voiceManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(cameraManager)
                .environmentObject(visionManager)
            }
        }
    }
    
    private func loadExercises() {
        isLoadingExercises = true
        
        // Check if we have a patient ID
        guard let patientId = UserDefaults.standard.string(forKey: "PatientID") else {
            // No patient ID, use example exercises
            exercises = Exercise.examples
            isLoadingExercises = false
            return
        }
        
        // Check if we have cached exercises
        if let exercisesData = UserDefaults.standard.data(forKey: "PatientExercises"),
           let exercisesJson = try? JSONSerialization.jsonObject(with: exercisesData) as? [[String: Any]] {
            
            print("🔍 DEBUG: Loading cached exercises")
            print("📦 DEBUG: Raw exercise data:", String(describing: exercisesJson))
            
            // Convert JSON to Exercise objects
            exercises = exercisesJson.compactMap { exerciseDict -> Exercise? in
                guard let name = exerciseDict["name"] as? String,
                      let description = exerciseDict["description"] as? String else {
                    return nil
                }
                
                // Extract instructions
                let instructions = (exerciseDict["instructions"] as? [String]) ?? []
                
                // Extract target joints
                let targetJointsStrings = (exerciseDict["target_joints"] as? [String]) ?? []
                let targetJoints = targetJointsStrings.compactMap { jointString -> Joint? in
                    if jointString.contains("knee") {
                        return jointString.contains("left") ? .leftKnee : .rightKnee
                    } else if jointString.contains("ankle") {
                        return jointString.contains("left") ? .leftAnkle : .rightAnkle
                    } else if jointString.contains("hip") {
                        return jointString.contains("left") ? .leftHip : .rightHip
                    }
                    return nil
                }
                
                // Get both exercise ID and patient exercise ID
                let exerciseId = exerciseDict["id"] as? String
                let patientExerciseId = exerciseDict["patient_exercise_id"] as? String
                
                print("🎯 DEBUG: Exercise ID:", exerciseId ?? "nil")
                print("🎯 DEBUG: Patient Exercise ID:", patientExerciseId ?? "nil")
                
                return Exercise(
                    id: UUID(),
                    name: name,
                    description: description,
                    imageURLString: exerciseDict["video_url"] as? String,
                    duration: 180, // Default duration
                    targetJoints: targetJoints.isEmpty ? [.leftKnee, .rightKnee] : targetJoints,
                    instructions: instructions.isEmpty ? ["Follow the video instructions"] : instructions,
                    firestoreId: exerciseId,
                    patientExerciseId: patientExerciseId
                )
            }
            
            isLoadingExercises = false
            
            // If we couldn't convert any exercises, use examples
            if exercises.isEmpty {
                exercises = Exercise.examples
            }
        } else {
            // No cached exercises, fetch from API
            fetchExercisesFromAPI(patientId: patientId)
        }
    }
    
    private func fetchExercisesFromAPI(patientId: String) {
        // API endpoint
        guard let url = URL(string: "https://us-central1-pep-pro.cloudfunctions.net/generate_exercises") else {
            self.exercises = Exercise.examples
            self.isLoadingExercises = false
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let requestBody: [String: Any] = [
            "patient_id": patientId,
            "llm_provider": "openai"
        ]
        
        // Convert data to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            self.exercises = Exercise.examples
            self.isLoadingExercises = false
            return
        }
        
        // Make API call
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching exercises: \(error)")
                    self.exercises = Exercise.examples
                    self.isLoadingExercises = false
                    return
                }
                
                guard let data = data else {
                    self.exercises = Exercise.examples
                    self.isLoadingExercises = false
                    return
                }
                
                do {
                    // Parse response
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? String,
                       status == "success",
                       let exercisesJson = json["exercises"] as? [[String: Any]] {
                        
                        // Store exercises in UserDefaults
                        if let exercisesData = try? JSONSerialization.data(withJSONObject: exercisesJson) {
                            UserDefaults.standard.set(exercisesData, forKey: "PatientExercises")
                        }
                        
                        // Convert JSON to Exercise objects
                        let parsedExercises: [Exercise] = exercisesJson.compactMap { exerciseDict -> Exercise? in
                            guard let name = exerciseDict["name"] as? String,
                                  let description = exerciseDict["description"] as? String else {
                                return nil
                            }
                            
                            let instructions = (exerciseDict["instructions"] as? [String]) ?? []
                            
                            let targetJointsStrings = (exerciseDict["target_joints"] as? [String]) ?? []
                            let targetJoints: [Joint] = targetJointsStrings.compactMap { jointString -> Joint? in
                                if jointString.contains("knee") {
                                    return jointString.contains("left") ? .leftKnee : .rightKnee
                                } else if jointString.contains("ankle") {
                                    return jointString.contains("left") ? .leftAnkle : .rightAnkle
                                } else if jointString.contains("hip") {
                                    return jointString.contains("left") ? .leftHip : .rightHip
                                }
                                return nil
                            }
                            
                            // Get both exercise ID and patient exercise ID
                            let exerciseId = exerciseDict["id"] as? String
                            let patientExerciseId = exerciseDict["patient_exercise_id"] as? String
                            
                            return Exercise(
                                id: UUID(),
                                name: name,
                                description: description,
                                imageURLString: exerciseDict["video_url"] as? String,
                                duration: 180,
                                targetJoints: targetJoints.isEmpty ? [.leftKnee, .rightKnee] : targetJoints,
                                instructions: instructions.isEmpty ? ["Follow the video instructions"] : instructions,
                                firestoreId: exerciseId,
                                patientExerciseId: patientExerciseId
                            )
                        }
                        
                        self.exercises = parsedExercises.isEmpty ? Exercise.examples : parsedExercises
                    } else {
                        self.exercises = Exercise.examples
                    }
                } catch {
                    print("Error parsing exercises: \(error)")
                    self.exercises = Exercise.examples
                }
                
                self.isLoadingExercises = false
            }
        }.resume()
    }
    
    private func checkPermissions() {
        resourceCoordinator.checkAllPermissions { allGranted in
            if !allGranted {
                showingPermissionsAlert = true
            }
        }
    }
}

struct ResetOnboardingButton: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingConfirmation = false
    @EnvironmentObject private var voiceManager: VoiceManager
    
    var body: some View {
        Button(action: {
            showingConfirmation = true
        }) {
            Text("Reset Onboarding")
                .foregroundColor(.red)
        }
        .confirmationDialog("Reset Onboarding?", isPresented: $showingConfirmation) {
            Button("Reset", role: .destructive) {
                voiceManager.resetOnboarding()
                hasCompletedOnboarding = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restart the onboarding process.")
        }
    }
}

// MARK: - Exercise Model Extension for compatibility with Joint enum
extension Exercise {
    // Convert from BodyJointType to Joint if needed
    init(id: UUID = UUID(), name: String, description: String,
         imageURLString: String? = nil, duration: TimeInterval = 180,
         targetJoints: [Joint] = [], instructions: [String] = [],
         firestoreId: String? = nil, patientExerciseId: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.imageURL = imageURLString != nil ? URL(string: imageURLString!) : nil
        self.duration = duration
        self.firestoreId = firestoreId
        self.patientExerciseId = patientExerciseId
        
        // Convert Joint to BodyJointType
        self.targetJoints = targetJoints.compactMap { joint in
            switch joint {
            case .leftKnee:
                return .leftKnee
            case .rightKnee:
                return .rightKnee
            case .leftAnkle:
                return .leftAnkle
            case .rightAnkle:
                return .rightAnkle
            case .leftHip:
                return .leftHip
            case .rightHip:
                return .rightHip
            }
        }
        
        self.instructions = instructions
    }
}
