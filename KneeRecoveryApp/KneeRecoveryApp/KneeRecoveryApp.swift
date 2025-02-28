import SwiftUI
import AVFoundation

@main
struct KneeRecoveryApp: App {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionManager = VisionManager()
    @StateObject private var voiceManager = VoiceManager()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @StateObject private var resourceCoordinator = ResourceCoordinator()
    
    // Add this environment object to monitor app lifecycle
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            LandingView()
                .environmentObject(cameraManager)
                .environmentObject(visionManager)
                .environmentObject(voiceManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(resourceCoordinator)
                .onAppear {
                    resourceCoordinator.configure(
                        cameraManager: cameraManager,
                        visionManager: visionManager,
                        voiceManager: voiceManager,
                        speechRecognitionManager: speechRecognitionManager
                    )
                }
        }
        // Add this to monitor app lifecycle and perform cleanup
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                // Clean up when app moves to background
                print("App moving to background - cleaning up resources")
                speechRecognitionManager.cleanUp()
                voiceManager.cleanUp()
                cameraManager.cleanUp()
                resourceCoordinator.stopExerciseSession()
                
                // Force deactivate audio session
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    print("Failed to deactivate audio session: \(error)")
                }
            }
        }
    }
}
