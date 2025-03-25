import SwiftUI

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
            targetJoints: [.leftKnee, .rightKnee],
            instructions: [
                "This exercise will be customized by you",
                "Add your own instructions in the exercise details"
            ]
        )
        
        // Add it to the exercises array
        exercises.append(newExercise)
        
        // In a real app, you would also call your API here
        // makeAPICall(name: name, voiceInstructions: voiceInstructions)
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

// MARK: - LandingView is the list of exercises
struct LandingView: View {
    @State private var exercises = Exercise.examples
    @State private var showingPermissionsAlert = false
    
    // Environment objects
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    @EnvironmentObject private var voiceManager: VoiceManager
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var visionManager: VisionManager
    
    var body: some View {
        NavigationView {
            List {
                if !exercises.isEmpty {
                    Section(header: Text("Your Recommended Exercises").font(.headline)) {
                        ForEach(exercises) { exercise in
                            NavigationLink {
                                // Destination view
                                ExerciseDetailView(exercise: exercise)
                                    .environmentObject(resourceCoordinator)
                                    .environmentObject(voiceManager)
                                    .environmentObject(speechRecognitionManager)
                                    .environmentObject(cameraManager)
                                    .environmentObject(visionManager)
                            } label: {
                                // Label view
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
                // Refresh exercises from the stored list
                exercises = Exercise.examples
                
                // End any ongoing voice session
                voiceManager.endElevenLabsSession()
                
                // Optional: Check if permissions are already granted
                resourceCoordinator.checkInitialPermissions()
            }
        }
        // Apply the custom modifier to handle add exercise sheet
        .withAddExerciseSheet(exercises: $exercises)
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
    
    var body: some View {
        Button(action: {
            showingConfirmation = true
        }) {
            Text("Reset Onboarding")
                .foregroundColor(.red)
        }
        .confirmationDialog("Reset Onboarding?", isPresented: $showingConfirmation) {
            Button("Reset", role: .destructive) {
                hasCompletedOnboarding = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restart the onboarding process.")
        }
    }
}
