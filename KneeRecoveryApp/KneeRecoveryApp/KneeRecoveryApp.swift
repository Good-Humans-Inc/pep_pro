import SwiftUI
import AVFoundation
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()

    return true
  }
}

@main
struct KneeRecoveryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionManager = VisionManager()
    @StateObject private var voiceManager = VoiceManager()
    @StateObject private var speechRecognitionManager = SpeechRecognitionManager()
    @StateObject private var resourceCoordinator = ResourceCoordinator()
    
    // State for onboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // Environment object to monitor app lifecycle
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
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
            }else{
                NavigationStack {
                    OnboardingView()
                        .environmentObject(voiceManager)
                        .environmentObject(resourceCoordinator)
                        .onDisappear{
                            hasCompletedOnboarding = true
                        }
                }
            }
            
        }
        // monitor app lifecycle and perform cleanup
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
