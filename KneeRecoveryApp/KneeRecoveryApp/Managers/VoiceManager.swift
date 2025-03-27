import Foundation
import AVFoundation
import Combine
import ElevenLabsSDK
import Network

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
    @Published var patientId: String? = nil
    
    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    @Published var isNetworkConnected = false
    
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
    
    // Notification name for patient ID updates
    static let patientIdReceivedNotification = Notification.Name("PatientIDReceived")
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        print("VoiceManager initialized with ElevenLabsSDK \(ElevenLabsSDK.version)")
        startNetworkMonitoring()
        
        // Check if we already have a patient ID
        if let existingPatientId = UserDefaults.standard.string(forKey: "PatientID") {
            DispatchQueue.main.async {
                self.patientId = existingPatientId
                print("🔄 Loaded existing patient ID: \(existingPatientId)")
            }
        }
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkConnected = path.status == .satisfied
                print("📶 Network status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
                print("📶 Interface: \(path.availableInterfaces.map { $0.name })")
                print("📶 Is expensive: \(path.isExpensive)")
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    // Initialize and start ElevenLabs conversation
    func startElevenLabsSession() {
        Task {
            do {
                print("⭐️ Starting ElevenLabs session with voice agent ID: \(voiceAgentID)")
                
                // Network check
                if !isNetworkConnected {
                    print("⚠️ Warning: Network appears to be disconnected")
                }
                
                // Set up initial configuration
                let config = ElevenLabsSDK.SessionConfig(agentId: voiceAgentID)
                
                // Register client tools
                var clientTools = ElevenLabsSDK.ClientTools()
                
                // Tool to capture patient ID
                clientTools.register("savePatientData") { [weak self] parameters in
                    guard let self = self else { return "Manager not available" }
                    
                    print("🔵 savePatientData tool called with parameters: \(parameters)")
                    
                    // Extract patient ID from parameters
                    guard let patientId = parameters["patient_id"] as? String else {
                        print("❌ No patient_id parameter found")
                        throw ElevenLabsSDK.ClientToolError.invalidParameters
                    }
                    
                    // Save patient ID to UserDefaults
                    UserDefaults.standard.set(patientId, forKey: "PatientID")
                    
                    // Update published property on main thread
                    DispatchQueue.main.async {
                        self.patientId = patientId
                        
                        // Post notification for other parts of the app
                        NotificationCenter.default.post(
                            name: VoiceManager.patientIdReceivedNotification,
                            object: nil,
                            userInfo: ["patient_id": patientId]
                        )
                    }
                    
                    print("✅ Saved patient ID: \(patientId)")
                    return "Patient data saved successfully with ID: \(patientId)"
                }
                
                // Debug tool to log any message
                clientTools.register("logMessage") { parameters in
                    guard let message = parameters["message"] as? String else {
                        throw ElevenLabsSDK.ClientToolError.invalidParameters
                    }
                    
                    print("🔵 ElevenLabs logMessage: \(message)")
                    return "Logged: \(message)"
                }
                
                // Tool to extract and save JSON data
                clientTools.register("saveJsonData") { [weak self] parameters in
                    guard let self = self else { return "Manager not available" }
                    
                    print("🔵 saveJsonData tool called with parameters: \(parameters)")
                    
                    // Process each key-value pair and save to UserDefaults if needed
                    for (key, value) in parameters {
                        print("📝 Key: \(key), Value: \(value)")
                        
                        // Special handling for patient_id
                        if key == "patient_id", let patientId = value as? String {
                            UserDefaults.standard.set(patientId, forKey: "PatientID")
                            
                            DispatchQueue.main.async {
                                self.patientId = patientId
                                
                                // Post notification
                                NotificationCenter.default.post(
                                    name: VoiceManager.patientIdReceivedNotification,
                                    object: nil,
                                    userInfo: ["patient_id": patientId]
                                )
                            }
                            
                            print("✅ Saved patient ID: \(patientId)")
                        }
                        
                        // Save other data to UserDefaults
                        if let stringValue = value as? String {
                            UserDefaults.standard.set(stringValue, forKey: key)
                        }
                    }
                    
                    return "JSON data processed successfully"
                }
                
                print("⭐️ Registered client tools: savePatientData, logMessage, saveJsonData")
                
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
                    print("📝 ElevenLabs message (\(role.rawValue)): \(message)")
                    
                    // Try to extract JSON from the message if possible
                    self.tryExtractJson(from: message)
                    
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
                    print("⚠️ ElevenLabs error: \(error)")
                    print("⚠️ Error details: \(String(describing: details))")
                    
                    DispatchQueue.main.async {
                        self.voiceError = "ElevenLabs error: \(error)"
                    }
                    
                    // If socket error, attempt reconnection
                    if error == "WebSocket error" {
                        self.handleConnectionFailure()
                    }
                }
                
                // Set status to connecting
                DispatchQueue.main.async {
                    self.status = .connecting
                }
                
                // Start the conversation session
                print("🚀 Attempting to start ElevenLabs session...")
                
                conversation = try await ElevenLabsSDK.Conversation.startSession(
                    config: config,
                    callbacks: callbacks,
                    clientTools: clientTools
                )
                
                DispatchQueue.main.async {
                    self.isListening = true
                }
                
                print("✅ ElevenLabs session started successfully")
                
            } catch {
                print("❌ Failed to start ElevenLabs conversation: \(error)")
                
                DispatchQueue.main.async {
                    self.voiceError = "Failed to start ElevenLabs: \(error.localizedDescription)"
                    self.status = .disconnected
                }
            }
        }
    }
    
    // Try to extract JSON from messages
    private func tryExtractJson(from message: String) {
        // Check if message might contain JSON
        if message.contains("{") && message.contains("}") {
            // Try to extract JSON using a simple approach first
            if let jsonStart = message.range(of: "{"),
               let jsonEnd = message.range(of: "}", options: .backwards) {
                
                let jsonStartIndex = jsonStart.lowerBound
                let jsonEndIndex = jsonEnd.upperBound
                let potentialJson = String(message[jsonStartIndex..<jsonEndIndex])
                
                do {
                    if let jsonData = potentialJson.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        
                        print("📊 Extracted JSON: \(json)")
                        
                        // Check for patient_id
                        if let patientId = json["patient_id"] as? String {
                            print("✅ Found patient ID in JSON: \(patientId)")
                            UserDefaults.standard.set(patientId, forKey: "PatientID")
                            
                            DispatchQueue.main.async {
                                self.patientId = patientId
                                
                                // Post notification
                                NotificationCenter.default.post(
                                    name: VoiceManager.patientIdReceivedNotification,
                                    object: nil,
                                    userInfo: ["patient_id": patientId]
                                )
                            }
                        }
                    }
                } catch {
                    print("❌ Failed to parse JSON: \(error)")
                }
            }
            
            // Alternative: Look for patient_id specifically with regex
            if message.contains("patient_id") {
                let pattern = "\"patient_id\"\\s*:\\s*\"([^\"]+)\""
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) {
                    
                    let idRange = Range(match.range(at: 1), in: message)!
                    let patientId = String(message[idRange])
                    
                    print("✅ Found patient ID using regex: \(patientId)")
                    UserDefaults.standard.set(patientId, forKey: "PatientID")
                    
                    DispatchQueue.main.async {
                        self.patientId = patientId
                        
                        // Post notification
                        NotificationCenter.default.post(
                            name: VoiceManager.patientIdReceivedNotification,
                            object: nil,
                            userInfo: ["patient_id": patientId]
                        )
                    }
                }
            }
        }
    }
    
    // Reconnection logic
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    
    private func handleConnectionFailure() {
        guard reconnectAttempt < maxReconnectAttempts else {
            print("⚠️ Maximum reconnection attempts reached")
            reconnectAttempt = 0
            return
        }
        
        let delay = pow(2.0, Double(reconnectAttempt)) // Exponential backoff
        reconnectAttempt += 1
        
        print("🔄 Attempting to reconnect in \(delay) seconds (attempt \(reconnectAttempt))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startElevenLabsSession()
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
