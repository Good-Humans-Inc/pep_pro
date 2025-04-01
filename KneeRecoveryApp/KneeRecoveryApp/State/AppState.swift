import Foundation
import SwiftUI
import Combine
import ElevenLabsSDK
import Vision

// MARK: - App State
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var isOnboardingComplete: Bool = false
    @Published var patientId: String? = nil
    @Published var exercises: [Exercise] = []
    @Published var currentExercise: Exercise? = nil
    @Published var isExerciseActive: Bool = false
    @Published var isGeneratingExercises: Bool = false
    @Published var exercisesGenerated: Bool = false
    
    // MARK: - Child States
    @Published var voiceState: VoiceState
    @Published var cameraState: CameraState
    @Published var speechState: SpeechState
    @Published var resourceState: ResourceState
    @Published var visionState: VisionState
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        self.voiceState = VoiceState()
        self.cameraState = CameraState()
        self.speechState = SpeechState()
        self.resourceState = ResourceState()
        self.visionState = VisionState()
        
        loadPersistedState()
        setupObservers()
    }
    
    // MARK: - State Management
    private func loadPersistedState() {
        // Load from UserDefaults
        isOnboardingComplete = UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
        patientId = UserDefaults.standard.string(forKey: "PatientID")
        
        // Load exercises if available
        if let exercisesData = UserDefaults.standard.data(forKey: "PatientExercises"),
           let exercisesJson = try? JSONSerialization.jsonObject(with: exercisesData) as? [[String: Any]] {
            exercises = exercisesJson.compactMap { exerciseDict -> Exercise? in
                // Convert JSON to Exercise objects
                // ... (implement conversion logic)
                return nil // Placeholder
            }
        }
    }
    
    private func setupObservers() {
        // No need for observers since child states are now @Published properties
    }
    
    // MARK: - State Updates
    func updateOnboardingState(completed: Bool) {
        isOnboardingComplete = completed
        UserDefaults.standard.set(completed, forKey: "HasCompletedOnboarding")
    }
    
    func updatePatientId(_ id: String) {
        patientId = id
        UserDefaults.standard.set(id, forKey: "PatientID")
    }
    
    func updateExercises(_ newExercises: [Exercise]) {
        exercises = newExercises
        if let exercisesData = try? JSONSerialization.data(withJSONObject: newExercises) {
            UserDefaults.standard.set(exercisesData, forKey: "PatientExercises")
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        voiceState.cleanup()
        cameraState.cleanup()
        speechState.cleanup()
        resourceState.cleanup()
        visionState.cleanup()
    }
}

// MARK: - Child States
class VoiceState: ObservableObject {
    @Published var isSpeaking = false
    @Published var isListening = false
    @Published var lastSpokenText: String = ""
    @Published var voiceError: String?
    @Published var status: ElevenLabsSDK.Status = .disconnected
    @Published var mode: ElevenLabsSDK.Mode = .listening
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText: String = ""
    @Published var isSessionActive = false
    @Published var currentAgentType: AgentType? = nil
    
    func cleanup() {
        isSpeaking = false
        isListening = false
        lastSpokenText = ""
        voiceError = nil
        status = .disconnected
        mode = .listening
        audioLevel = 0.0
        transcribedText = ""
        isSessionActive = false
        currentAgentType = nil
    }
}

class CameraState: ObservableObject {
    @Published var isSessionRunning = false
    @Published var isCameraAuthorized = false
    @Published var cameraError: String?
    
    func cleanup() {
        isSessionRunning = false
        isCameraAuthorized = false
        cameraError = nil
    }
}

class SpeechState: ObservableObject {
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var isSpeechAuthorized = false
    @Published var speechError: String?
    
    func cleanup() {
        isListening = false
        recognizedText = ""
        isSpeechAuthorized = false
        speechError = nil
    }
}

class ResourceState: ObservableObject {
    @Published var isInitialized = false
    @Published var isCleaningUp = false
    @Published var error: String?
    
    func cleanup() {
        isInitialized = false
        isCleaningUp = false
        error = nil
    }
}

// MARK: - Vision State
class VisionState: ObservableObject {
    @Published var currentPose = BodyPose()
    @Published var isProcessing = false
    @Published var error: String?
    @Published var detectedPoses: [VNHumanBodyPoseObservation] = []
    
    func cleanup() {
        currentPose = BodyPose()
        isProcessing = false
        error = nil
        detectedPoses.removeAll()
    }
} 
