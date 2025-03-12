import SwiftUI

struct LandingView: View {
    @State private var exercises = Exercise.examples
    @State private var showingPermissionsAlert = false
    
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    @EnvironmentObject private var voiceManager: VoiceManager
    
    var body: some View {
        NavigationView {
            List {
                if !exercises.isEmpty {
                    Section(header: Text("Your Recommended Exercises").font(.headline)) {
                        ForEach(exercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                ExerciseCard(exercise: exercise)
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
                    // Check permissions before continuing
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
                if let _ = resourceCoordinator as ResourceCoordinator? {
                    resourceCoordinator.checkInitialPermissions()
                }
            }
        }
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
