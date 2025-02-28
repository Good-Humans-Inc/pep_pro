import SwiftUI

struct LandingView: View {
    @State private var exercises = Exercise.examples
    @State private var showingPermissionsAlert = false
    
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    
    var body: some View {
        NavigationView {
            List {
                ForEach(exercises) { exercise in
                    NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                        ExerciseCard(exercise: exercise)
                    }
                }
            }
            .navigationTitle("Knee Recovery Exercises")
            .navigationBarItems(trailing: Button(action: {
                // Check permissions before continuing
                checkPermissions()
            }) {
                Image(systemName: "info.circle")
            })
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
                // Optional: Check if permissions are already granted
                resourceCoordinator.checkInitialPermissions()
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

struct LandingView_Previews: PreviewProvider {
    static var previews: some View {
        LandingView()
            .environmentObject(ResourceCoordinator())
    }
}
