import SwiftUI
import AVFoundation

struct ContentView: View {
    // Create a single instance of AppState
    @StateObject private var appState: AppState
    
    // Initialize other managers lazily using AppState
    @StateObject private var voiceManager: VoiceManager
    @StateObject private var cameraManager: CameraManager
    @StateObject private var speechRecognitionManager: SpeechRecognitionManager
    @StateObject private var resourceCoordinator: ResourceCoordinator
    @StateObject private var visionManager: VisionManager
    
    init() {
        // Create a single instance of AppState
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        
        // Initialize all managers with the same AppState instance
        _voiceManager = StateObject(wrappedValue: VoiceManager(appState: state))
        _cameraManager = StateObject(wrappedValue: CameraManager(appState: state))
        _speechRecognitionManager = StateObject(wrappedValue: SpeechRecognitionManager(appState: state))
        _resourceCoordinator = StateObject(wrappedValue: ResourceCoordinator(appState: state))
        _visionManager = StateObject(wrappedValue: VisionManager(appState: state))
    }
    
    var body: some View {
        if appState.isOnboardingComplete {
            LandingView()
                .environmentObject(appState)
                .environmentObject(voiceManager)
                .environmentObject(cameraManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(resourceCoordinator)
                .environmentObject(visionManager)
                .onAppear {
                    // Configure resource coordinator
                    resourceCoordinator.configure(
                        cameraManager: cameraManager,
                        visionManager: visionManager,
                        voiceManager: voiceManager,
                        speechRecognitionManager: speechRecognitionManager
                    )
                    
                    // Ensure any lingering sessions are terminated
                    if voiceManager.isSessionActive {
                        print("⚠️ Terminating lingering voice session")
                        voiceManager.endElevenLabsSession()
                    }
                }
                .onDisappear {
                    // Clean up resources when view disappears
                    cleanupResources()
                }
        } else {
            OnboardingView()
                .environmentObject(appState)
                .environmentObject(voiceManager)
                .environmentObject(cameraManager)
                .environmentObject(speechRecognitionManager)
                .environmentObject(resourceCoordinator)
                .environmentObject(visionManager)
                .onAppear {
                    // Configure resource coordinator
                    resourceCoordinator.configure(
                        cameraManager: cameraManager,
                        visionManager: visionManager,
                        voiceManager: voiceManager,
                        speechRecognitionManager: speechRecognitionManager
                    )
                    
                    // Ensure any lingering sessions are terminated
                    if voiceManager.isSessionActive {
                        print("⚠️ Terminating lingering voice session")
                        voiceManager.endElevenLabsSession()
                    }
                }
                .onDisappear {
                    // Clean up resources when view disappears
                    cleanupResources()
                }
        }
 
    }
    
    private func cleanupResources() {
        speechRecognitionManager.cleanUp()
        voiceManager.cleanUp()
        cameraManager.cleanUp()
        resourceCoordinator.stopExerciseSession()
        visionManager.cleanUp()
        
        // Force deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Audio session deactivated")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
    }
}

