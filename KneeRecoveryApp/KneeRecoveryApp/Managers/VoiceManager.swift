import Foundation
import AVFoundation
import Combine
import ElevenLabsSDK

class VoiceManager: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var isSpeaking = false
    @Published var isListening = false
    @Published var lastSpokenText: String = ""
    @Published var voiceError: String?
    @Published var status: ElevenLabsSDK.Status = .disconnected
    @Published var mode: ElevenLabsSDK.Mode = .listening
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText: String = ""
    
    // Local speech synthesizer as fallback only
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    
    // ElevenLabs conversation
    private var conversation: ElevenLabsSDK.Conversation?
    
    // Voice agent ID
    private let voiceAgentID = "lpwQ9rz6CHbfexAY8kU3"
    
    // Audio session
    private let audioSession = AVAudioSession.sharedInstance()
    
    // Completion handler for speech
    private var completionHandler: (() -> Void)?
    
    // Observer for status changes
    private var statusObserver: AnyCancellable?
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        print("VoiceManager initialized with ElevenLabsSDK \(ElevenLabsSDK.version)")
    }
    
    // Initialize and start ElevenLabs conversation
    func startElevenLabsSession() {
        Task {
            do {
                print("Starting ElevenLabs session with voice agent ID: \(voiceAgentID)")
                
                // Set up initial configuration
                let config = ElevenLabsSDK.SessionConfig(agentId: voiceAgentID)
                
                // Configure callbacks for ElevenLabs events
                var callbacks = ElevenLabsSDK.Callbacks()
                
                // Connection status callbacks
                callbacks.onConnect = { conversationId in
                    print("🟢 ElevenLabs connected with conversation ID: \(conversationId)")
                    DispatchQueue.main.async {
                        self.status = .connected
                    }
                }
                
                callbacks.onDisconnect = {
                    print("🔴 ElevenLabs disconnected")
                    DispatchQueue.main.async {
                        self.status = .disconnected
                    }
                }
                
                // Mode change callback (speaking/listening)
                callbacks.onModeChange = { newMode in
                    print("🔄 ElevenLabs mode changed to: \(newMode)")
                    DispatchQueue.main.async {
                        self.mode = newMode
                        self.isSpeaking = (newMode == .speaking)
                        self.isListening = (newMode == .listening)
                    }
                }
                
                // Audio level updates
                callbacks.onVolumeUpdate = { newVolume in
                    DispatchQueue.main.async {
                        self.audioLevel = newVolume
                    }
                }
                
                // Message transcripts
                callbacks.onMessage = { message, role in
                    print("📝 ElevenLabs message: \(message) (role: \(role.rawValue))")
                    
                    DispatchQueue.main.async {
                        if role == .user {
                            self.transcribedText = message
                        } else if role == .ai {
                            self.lastSpokenText = message
                        }
                    }
                }
                
                // Error handling
                callbacks.onError = { error, details in
                    print("⚠️ ElevenLabs error: \(error), details: \(String(describing: details))")
                    
                    DispatchQueue.main.async {
                        self.voiceError = "ElevenLabs error: \(error)"
                    }
                }
                
                // Set status to connecting
                DispatchQueue.main.async {
                    self.status = .connecting
                }
                
                // Start the conversation session
                conversation = try await ElevenLabsSDK.Conversation.startSession(
                    config: config,
                    callbacks: callbacks
                )
                
                DispatchQueue.main.async {
                    self.isListening = true
                }
                
                print("🚀 ElevenLabs session started successfully")
            } catch {
                print("❌ Failed to start ElevenLabs conversation: \(error)")
                
                DispatchQueue.main.async {
                    self.voiceError = "Failed to start ElevenLabs: \(error.localizedDescription)"
                    self.status = .disconnected
                }
            }
        }
    }
    
    // End the ElevenLabs conversation session
    func endElevenLabsSession() {
        Task {
            guard let conversation = self.conversation else {
                print("No active ElevenLabs session to end")
                return
            }
            
            print("Ending ElevenLabs session")
            conversation.endSession()
            
            DispatchQueue.main.async {
                self.conversation = nil
                self.status = .disconnected
                self.isListening = false
                self.isSpeaking = false
                print("ElevenLabs session ended")
            }
        }
    }
    
    // Speak text using the system's speech synthesizer (fallback only)
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        lastSpokenText = text
        self.completionHandler = completion
        
        // If ElevenLabs is connected, we don't need this - the agent responds
        // to user voice input automatically. This is just a fallback.
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.speechSynthesizer.speak(utterance)
        }
    }
    
    // Pause listening (temporarily stop receiving audio input)
    func pauseListening() {
        guard let conversation = conversation, status == .connected else {
            return
        }
        
        conversation.stopRecording()
        isListening = false
        print("ElevenLabs listening paused")
    }
    
    // Resume listening (start receiving audio input again)
    func resumeListening() {
        guard let conversation = conversation, status == .connected else {
            return
        }
        
        conversation.startRecording()
        isListening = true
        print("ElevenLabs listening resumed")
    }
    
    // Interrupt speech if the agent is currently speaking
    func stopSpeaking() {
        // First try to interrupt ElevenLabs speech if active
        if let conversation = conversation, status == .connected, mode == .speaking {
            Task {
                do {
                    print("Interrupting ElevenLabs speech")
                    try await conversation.endSession()
                } catch {
                    print("Failed to interrupt ElevenLabs speech: \(error)")
                }
            }
        }
        
        // Stop system speech if active (fallback)
        DispatchQueue.main.async {
            if self.speechSynthesizer.isSpeaking {
                self.speechSynthesizer.stopSpeaking(at: .immediate)
            }
            
            self.isSpeaking = false
        }
    }
    
    // Clean up all resources
    func cleanUp() {
        print("Cleaning up VoiceManager resources")
        
        // Stop speaking and end session
        stopSpeaking()
        endElevenLabsSession()
        
        // Reset state
        DispatchQueue.main.async {
            self.transcribedText = ""
            self.lastSpokenText = ""
        }
        
        // Deactivate audio session
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("Audio session deactivated")
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // Get the conversation ID if available
    func getConversationId() -> String? {
        guard let conversation = conversation, status == .connected else {
            return nil
        }
        
        return conversation.getId()
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.completionHandler?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.completionHandler?()
        }
    }
}
