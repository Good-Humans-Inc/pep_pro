import Foundation
import AVFoundation
import Combine
import Speech

class ResourceCoordinator: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var isExerciseSessionActive = false
    @Published var allPermissionsGranted = false
    @Published var coordinationError: String?
    
    // Audio session manager
    private let audioSession = AVAudioSession.sharedInstance()
    
    // References to the managers this coordinator will manage
    private var cameraManager: CameraManager?
    private var visionManager: VisionManager?
    private var voiceManager: VoiceManager?
    private var speechRecognitionManager: SpeechRecognitionManager?
    
    // Audio queue to manage voice and speech recognition timing
    private var audioQueue = [AudioOperation]()
    private var isProcessingAudioQueue = false
    
    // Audio operation struct for queuing
    private struct AudioOperation {
        enum OperationType {
            case speak
            case listen
        }
        
        let type: OperationType
        let data: Any?
        let completion: (() -> Void)?
        
        init(type: OperationType, data: Any? = nil, completion: (() -> Void)? = nil) {
            self.type = type
            self.data = data
            self.completion = completion
        }
    }
    
    func configure(cameraManager: CameraManager, visionManager: VisionManager,
                   voiceManager: VoiceManager, speechRecognitionManager: SpeechRecognitionManager) {
        self.cameraManager = cameraManager
        self.visionManager = visionManager
        self.voiceManager = voiceManager
        self.speechRecognitionManager = speechRecognitionManager
    }
    
    // MARK: - Permission Handling
    
    func checkInitialPermissions() {
        checkAllPermissions { _ in /* No action needed on initial check */ }
    }
    
    func checkAllPermissions(completion: @escaping (Bool) -> Void) {
        // Reset the permission flag
        allPermissionsGranted = false
        
        // Check camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        // Check microphone permission - using updated API
        var microphoneGranted = false
        
        // Use the appropriate API based on iOS version
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                microphoneGranted = granted
                
                // Check speech recognition permission
                SFSpeechRecognizer.requestAuthorization { speechStatus in
                    DispatchQueue.main.async {
                        // All permissions are granted if:
                        // 1. Camera is authorized
                        // 2. Microphone is authorized
                        // 3. Speech recognition is authorized
                        let allGranted = (cameraStatus == .authorized) &&
                                        microphoneGranted &&
                                        (speechStatus == .authorized)
                        
                        self.allPermissionsGranted = allGranted
                        completion(allGranted)
                    }
                }
            }
        } else {
            // Use the older API for iOS 16 and below
            audioSession.requestRecordPermission { granted in
                microphoneGranted = granted
                
                // Check speech recognition permission
                SFSpeechRecognizer.requestAuthorization { speechStatus in
                    DispatchQueue.main.async {
                        // All permissions are granted if:
                        // 1. Camera is authorized
                        // 2. Microphone is authorized
                        // 3. Speech recognition is authorized
                        let allGranted = (cameraStatus == .authorized) &&
                                        microphoneGranted &&
                                        (speechStatus == .authorized)
                        
                        self.allPermissionsGranted = allGranted
                        completion(allGranted)
                    }
                }
            }
        }
    }
    
    // MARK: - Exercise Session Management
    
    func startExerciseSession(completion: @escaping (Bool) -> Void) {
        // Check permissions first
        checkAllPermissions { allGranted in
            guard allGranted else {
                self.coordinationError = "Missing required permissions"
                completion(false)
                return
            }
            
            // Set up a single audio session for everything
            do {
                // This is the key configuration that works for both speech and audio
                try self.audioSession.setCategory(.playAndRecord,
                                              mode: .spokenAudio,
                                              options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                try self.audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                print("Master audio session configured")
            } catch {
                self.coordinationError = "Failed to configure audio session: \(error.localizedDescription)"
                completion(false)
                return
            }
            
            // Now we're in an active exercise session
            self.isExerciseSessionActive = true
            completion(true)
        }
    }
    
    func stopExerciseSession() {
        // Clear audio queue
        audioQueue.removeAll()
        isProcessingAudioQueue = false
        
        // Stop the camera session
        cameraManager?.stopSession()
        
        // Stop vision processing
        visionManager?.stopProcessing()
        
        // Stop speech synthesis
        voiceManager?.stopSpeaking()
        
        // Stop speech recognition
        speechRecognitionManager?.stopListening()
        
        // Deactivate audio session
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
        
        // Update state
        isExerciseSessionActive = false
    }
    
    // MARK: - Audio Queue Management
    
    // Queue an operation to speak text
    func queueSpeech(_ text: String, completion: (() -> Void)? = nil) {
        let operation = AudioOperation(type: .speak, data: text, completion: completion)
        audioQueue.append(operation)
        
        if !isProcessingAudioQueue {
            processNextAudioOperation()
        }
    }
    
    // Queue an operation to listen for speech
    func queueListen(duration: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        let operation = AudioOperation(type: .listen, data: duration, completion: completion)
        audioQueue.append(operation)
        
        if !isProcessingAudioQueue {
            processNextAudioOperation()
        }
    }
    
    // Process the next operation in the queue
    private func processNextAudioOperation() {
        guard !audioQueue.isEmpty else {
            isProcessingAudioQueue = false
            return
        }
        
        isProcessingAudioQueue = true
        let operation = audioQueue.removeFirst()
        
        switch operation.type {
        case .speak:
            if let text = operation.data as? String {
                // Ensure speech recognition is paused
                speechRecognitionManager?.stopListening()
                
                // Start speaking
                voiceManager?.speak(text) { [weak self] in
                    guard let self = self else { return }
                    
                    // Execute completion handler
                    operation.completion?()
                    
                    // Process next operation
                    self.processNextAudioOperation()
                }
            } else {
                // Invalid operation, move to next
                operation.completion?()
                processNextAudioOperation()
            }
            
        case .listen:
            // Ensure speech synthesis is stopped
            voiceManager?.stopSpeaking()
            
            // Start listening
            speechRecognitionManager?.startListening()
            
            // If a duration was specified, stop listening after that time
            if let duration = operation.data as? TimeInterval {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    guard let self = self else { return }
                    
                    // Stop listening
                    self.speechRecognitionManager?.stopListening()
                    
                    // Execute completion handler
                    operation.completion?()
                    
                    // Process next operation
                    self.processNextAudioOperation()
                }
            } else {
                // If no duration, let the next operation in queue determine when to stop
                operation.completion?()
                processNextAudioOperation()
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func getJointTracking() -> BodyPose? {
        return visionManager?.currentBodyPose
    }
    
    // MARK: - Simple Diagnostic Methods
    
    func testMicrophoneInput() {
        // This function creates a simple test to check if the microphone is working
        print("Testing microphone input...")
        
        // Set up audio session for recording
        do {
            try self.audioSession.setCategory(.record, mode: .measurement)
            try self.audioSession.setActive(true)
            
            // Create a simple audio engine for testing
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Install a tap to check for audio levels
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, time in
                // Get the buffer data
                let channelData = buffer.floatChannelData?[0]
                if let data = channelData {
                    // Simple calculation of audio level without Accelerate framework
                    var sum: Float = 0.0
                    let frameLength = Int(buffer.frameLength)
                    
                    for i in 0..<frameLength {
                        let sample = data[i]
                        sum += sample * sample
                    }
                    
                    if frameLength > 0 {
                        let rms = sqrt(sum / Float(frameLength))
                        let db = 20 * log10(max(rms, 0.0000001))
                        print("MICROPHONE TEST - AUDIO LEVEL: \(db) dB")
                    }
                }
            }
            
            // Start the engine
            engine.prepare()
            try engine.start()
            
            print("Microphone test started... speak into microphone")
            
            // Run for 5 seconds
            Thread.sleep(forTimeInterval: 5.0)
            
            // Stop engine
            engine.stop()
            inputNode.removeTap(onBus: 0)
            
            try self.audioSession.setActive(false)
            
            print("Microphone test complete")
        } catch {
            print("Microphone test error: \(error)")
        }
    }
    
    func printAudioRouteInfo() {
        // Print detailed information about the current audio route
        let currentRoute = audioSession.currentRoute
        
        print("AUDIO ROUTE INFORMATION:")
        print("- Inputs:")
        for input in currentRoute.inputs {
            print("  • \(input.portName) (Type: \(input.portType.rawValue))")
        }
        
        print("- Outputs:")
        for output in currentRoute.outputs {
            print("  • \(output.portName) (Type: \(output.portType.rawValue))")
        }
    }
}
