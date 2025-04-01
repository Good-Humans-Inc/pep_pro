import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognitionManager: NSObject, ObservableObject {
    // Reference to AppState
    private let appState: AppState
    
    // Published properties for UI updates
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var isSpeechAuthorized = false
    @Published var speechError: String?
    
    // Speech recognition objects
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // User's speech history
    private var speechHistory: [String] = []
    
    // For tracking previously seen text to detect changes
    private var lastTranscription = ""
    
    // Initialize with AppState
    init(appState: AppState) {
        self.appState = appState
        super.init()
        
        // Update speech state
        updateSpeechState(isListening: isListening)
        updateSpeechState(recognizedText: recognizedText)
        updateSpeechState(isAuthorized: isSpeechAuthorized)
        
        checkAuthorization()
    }
    
    func checkAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch status {
                case .authorized:
                    self.isSpeechAuthorized = true
                    print("Speech recognition authorization granted")
                case .denied:
                    self.isSpeechAuthorized = false
                    self.speechError = "Speech recognition authorization denied"
                    print("Speech recognition authorization denied")
                case .restricted:
                    self.isSpeechAuthorized = false
                    self.speechError = "Speech recognition restricted on this device"
                    print("Speech recognition restricted on this device")
                case .notDetermined:
                    self.isSpeechAuthorized = false
                    self.speechError = "Speech recognition authorization not determined"
                    print("Speech recognition authorization not determined")
                @unknown default:
                    self.isSpeechAuthorized = false
                    self.speechError = "Unknown authorization status"
                    print("Unknown speech recognition authorization status")
                }
            }
        }
    }
    
    func startListening() {
        print("Starting speech recognition...")
        
        // Ensure we're not already listening
        if isListening {
            stopListening()
        }
        
        // Make sure previous task is cancelled
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
            print("Cancelled existing recognition task")
        }
        
        // Check if speech recognizer is available
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            speechError = "Speech recognizer is not available"
            print("ERROR: Speech recognizer is not available")
            return
        }
        
        // Configure audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Important: Use options that work alongside other audio
            try audioSession.setCategory(.playAndRecord,
                                      mode: .spokenAudio,
                                      options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured for speech recognition")
        } catch {
            speechError = "Could not configure audio session: \(error.localizedDescription)"
            print("AUDIO SESSION ERROR: \(error)")
            return
        }
        
        // Create and configure the speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            speechError = "Could not create speech recognition request"
            print("ERROR: Could not create speech recognition request")
            return
        }
        
        // Configure for continuous recognition
        recognitionRequest.shouldReportPartialResults = true
        print("Recognition request configured with partial results enabled")
        
        // Configure audio input
        let inputNode = audioEngine.inputNode
        print("Got input node: \(inputNode)")
        
        // Get the recording format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("Recording format: \(recordingFormat)")
        
        
        // *******DEBUG Crashing
        // CRITICAL: Make a copy of the format to avoid reference issues
        let processFormat = AVAudioFormat(
            commonFormat: recordingFormat.commonFormat,
            sampleRate: recordingFormat.sampleRate,
            channels: recordingFormat.channelCount,
            interleaved: recordingFormat.isInterleaved
        )
        
        // Install tap with the copied format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: processFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
            // Rest of your code
        }
        
        // Create recognition task with detailed logging
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("RECOGNITION ERROR: \(error.localizedDescription)")
                self.speechError = "Recognition error: \(error.localizedDescription)"
            }
            
            if let result = result {
                // Get the transcription
                let transcription = result.bestTranscription.formattedString
                
                // Only update and log if the text has changed
                if transcription != self.lastTranscription {
                    print("RECOGNIZED TEXT: \(transcription)")
                    self.lastTranscription = transcription
                    
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        self.recognizedText = transcription
                    }
                }
                
                // Handle final results
                if result.isFinal {
                    print("FINAL RECOGNITION: \(transcription)")
                    self.processSpeech(transcription)
                }
            }
            
            // If we have a final result or an error, clean up and potentially restart
            if (result?.isFinal ?? false) || error != nil {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Restart if we should still be listening
                if self.isListening {
                    print("Restarting speech recognition after final result")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startListening()
                    }
                } else {
                    print("Speech recognition ended")
                }
            }
        }
        
        // Configure the microphone input with a relatively large buffer size for stability
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            // Append the audio buffer to the recognition request
            self.recognitionRequest?.append(buffer)
            
            // Log audio levels occasionally for debugging
            if arc4random_uniform(100) < 10 { // 10% chance to log
                // Simple calculation of audio level
                if let channelData = buffer.floatChannelData?[0] {
                    var sum: Float = 0.0
                    let frameLength = Int(buffer.frameLength)
                    
                    for i in 0..<frameLength {
                        let sample = channelData[i]
                        sum += sample * sample
                    }
                    
                    if frameLength > 0 {
                        let rms = sqrt(sum / Float(frameLength))
                        let db = 20 * log10(max(rms, 0.0000001))
                        print("AUDIO LEVEL: \(db) dB")
                    }
                }
            }
        }
        
        // *****DEBUG Crashing
        // Add this before audioEngine.prepare()
        do {
            // Reset the audio session to make sure it's in a clean state
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            try audioSession.setCategory(.playAndRecord,
                                      mode: .spokenAudio,
                                      options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("FINAL AUDIO SESSION CONFIG ERROR: \(error)")
            speechError = "Could not configure audio session: \(error.localizedDescription)"
            return
        }
        // Start the audio engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isListening = true
            print("Speech recognition started successfully - Audio engine running: \(audioEngine.isRunning)")
        } catch {
            speechError = "Could not start audio engine: \(error.localizedDescription)"
            print("AUDIO ENGINE ERROR: \(error)")
            isListening = false
        }
    }
    
    func stopListening() {
        print("Stopping speech recognition...")
        
        // Stop the audio engine and remove the tap
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // End the recognition request
        recognitionRequest?.endAudio()
        
        // Cancel the recognition task
        recognitionTask?.cancel()
        
        // Clear state
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        
        print("Speech recognition stopped")
    }
    
    private func processSpeech(_ text: String) {
        // Add to history
        speechHistory.append(text)
        
        // Process the speech - implement custom logic based on what user says
        print("User said: \(text)")
        
        // Reset for next utterance
        recognizedText = ""
        lastTranscription = ""
    }
    
    // Get the recent speech history
    func getRecentSpeechHistory(limit: Int = 5) -> [String] {
        let endIndex = min(speechHistory.count, limit)
        return Array(speechHistory.suffix(endIndex))
    }
    
    // Clean up method
    func cleanUp() {
        isListening = false
        recognizedText = ""
        updateSpeechState(isListening: false, recognizedText: "")
    }
    
    // Update speech state in AppState
    private func updateSpeechState(isListening: Bool? = nil, recognizedText: String? = nil, isAuthorized: Bool? = nil, error: String? = nil) {
        DispatchQueue.main.async {
            if let isListening = isListening {
                self.appState.speechState.isListening = isListening
            }
            if let recognizedText = recognizedText {
                self.appState.speechState.recognizedText = recognizedText
            }
            if let isAuthorized = isAuthorized {
                self.appState.speechState.isSpeechAuthorized = isAuthorized
            }
            if let error = error {
                self.appState.speechState.speechError = error
            }
        }
    }
}
