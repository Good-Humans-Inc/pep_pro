import Foundation
import AVFoundation
import Combine
import ElevenLabsSDK
import Network

// Define agent types
enum AgentType {
    case onboarding
    case exerciseCoach
    
    var agentId: String {
        switch self {
        case .onboarding:
            return "lpwQ9rz6CHbfexAY8kU3"   // Onboarding agent ID
        case .exerciseCoach:
            return "GEXRBIHrq3oa2fB0TO1v"   // Exercise coach agent ID - now vanilla
        }
    }
    
    var displayName: String {
        switch self {
        case .onboarding:
            return "Onboarding Assistant"
        case .exerciseCoach:
            return "Exercise Coach"
        }
    }
}

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
    @Published var isGeneratingExercises = false
    @Published var exercisesGenerated = false
    @Published var hasCompletedOnboarding = false
    @Published var isSessionActive = false  // Track if the session is active
    @Published var currentAgentType: AgentType? = nil
    
    // Track session operations
    private var sessionOperationInProgress = false
    private var sessionOperationCompletionHandlers: [() -> Void] = []
    
    // Track session request flags separately for each agent type
    private var sessionRequestFlags: [AgentType: Bool] = [
        .onboarding: false,
        .exerciseCoach: false
    ]
    
    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    @Published var isNetworkConnected = false
    
    // Local speech synthesizer as fallback only
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    // ElevenLabs conversation
    private var conversation: ElevenLabsSDK.Conversation?
    
    // Audio session
    private let audioSession = AVAudioSession.sharedInstance()
    
    // API endpoints
    private let generateExercisesEndpoint = "https://us-central1-pep-pro.cloudfunctions.net/generate_exercises"
    
    // Completion handler for speech
    private var completionHandler: (() -> Void)?
    
    // Observer for status changes
    private var statusObserver: AnyCancellable?
    
    // NSlock for thread safety
    private let sessionLock = NSLock()
    
    // Flag to track if audio session is being configured
    private var isConfiguringAudio = false

    // Cleanup flag to prevent race conditions during cleanup
    private var isPerformingCleanup = false
    
    // Notification names
    static let patientIdReceivedNotification = Notification.Name("PatientIDReceived")
    static let exercisesGeneratedNotification = Notification.Name("ExercisesGenerated")
    static let onboardingCompletedNotification = Notification.Name("OnboardingCompleted")
    static let exerciseCoachReadyNotification = Notification.Name("ExerciseCoachReady")
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        print("VoiceManager initialized with ElevenLabsSDK \(ElevenLabsSDK.version)")
        startNetworkMonitoring()
        
        // Check if we already have a patient ID (indicates completed onboarding)
        if let existingPatientId = UserDefaults.standard.string(forKey: "PatientID") {
            DispatchQueue.main.async {
                self.patientId = existingPatientId
                self.hasCompletedOnboarding = true
                print("🔄 Loaded existing patient ID: \(existingPatientId)")
            }
        }
        
        // Check if onboarding is explicitly marked as completed
        if UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") {
            DispatchQueue.main.async {
                self.hasCompletedOnboarding = true
                print("🔄 Onboarding already completed according to UserDefaults")
            }
        }
    }
    
    // Method to wait for session operations to complete
    private func waitForSessionOperations(completion: @escaping () -> Void) {
        if sessionOperationInProgress {
            // Add to queue of completion handlers
            sessionOperationCompletionHandlers.append(completion)
        } else {
            // Execute immediately
            completion()
        }
    }

    // Method to complete current operation and process queue
    private func completeSessionOperation() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.sessionOperationInProgress = false
            
            // Process any queued operations
            if !self.sessionOperationCompletionHandlers.isEmpty {
                let nextOperation = self.sessionOperationCompletionHandlers.removeFirst()
                nextOperation()
            }
        }
    }
    
    func resetOnboarding() {
        print("🔄 Resetting onboarding state")
        
        // End any active session
        endElevenLabsSession()
        
        // Reset session flags
        sessionRequestFlags[.onboarding] = false
        sessionRequestFlags[.exerciseCoach] = false
        
        // Clear onboarding status flags
        DispatchQueue.main.async {
            self.hasCompletedOnboarding = false
            self.patientId = nil
            self.exercisesGenerated = false
            self.isSessionActive = false
            self.currentAgentType = nil
        }
        
        // Clear UserDefaults values
        UserDefaults.standard.removeObject(forKey: "PatientID")
        UserDefaults.standard.removeObject(forKey: "HasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "PatientExercises")
        
        print("✅ Onboarding reset complete")
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
    
    // Main method to start an ElevenLabs session with specified agent type
    func startElevenLabsSession(agentType: AgentType = .onboarding, completion: (() -> Void)? = nil) {
        // Use a lock to prevent concurrent session starts
        sessionLock.lock()
        
        // Early check for conditions that would prevent start
        if isPerformingCleanup {
            print("⚠️ Cannot start session during cleanup")
            sessionLock.unlock()
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        // Check if we already have an active session
        if isSessionActive {
            print("⚠️ A session is already active (\(currentAgentType?.displayName ?? "unknown")). Ending it before starting a new one.")
            
            // Release the lock
            sessionLock.unlock()
            
            // End current session and then start the new one
            endElevenLabsSession { [weak self] in
                guard let self = self else { return }
                // Add delay to ensure cleanup is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startElevenLabsSession(agentType: agentType, completion: completion)
                }
            }
            return
        }
        
        // Check if onboarding is already completed (for onboarding agent)
        if agentType == .onboarding && hasCompletedOnboarding {
            print("⚠️ Onboarding already completed, skipping session start")
            sessionLock.unlock()
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        // Check if this agent type is already being requested
        if sessionRequestFlags[agentType] == true {
            print("⚠️ \(agentType.displayName) session already requested, skipping duplicate start")
            sessionLock.unlock()
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        // Mark this session as requested
        sessionRequestFlags[agentType] = true
        currentAgentType = agentType
        
        // Track this operation
        sessionOperationInProgress = true
        
        print("🔒 Marked \(agentType.displayName) session as requested")
        
        // Release the lock now that we've updated our state
        sessionLock.unlock()
        
        // Start the actual session
        doStartElevenLabsSession(agentType: agentType) {
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    private func doStartElevenLabsSession(agentType: AgentType, completion: @escaping () -> Void) {
        Task {
            do {
                print("⭐️ Starting ElevenLabs session with agent type: \(agentType.displayName) (ID: \(agentType.agentId))")
                
                // Configure audio session - with proper async/await
                await configureAudioSessionForElevenLabs()
                
                // Network check
                if !isNetworkConnected {
                    print("⚠️ Warning: Network appears to be disconnected")
                }
                
                // Set up initial configuration
                let config = ElevenLabsSDK.SessionConfig(agentId: agentType.agentId)
                
                // Register client tools - different tools based on agent type
                var clientTools = ElevenLabsSDK.ClientTools()
                
                switch agentType {
                case .onboarding:
                    registerOnboardingTools(clientTools: &clientTools)
                case .exerciseCoach:
                    registerExerciseCoachTools(clientTools: &clientTools)
                }
                
                // Configure callbacks for ElevenLabs events
                var callbacks = ElevenLabsSDK.Callbacks()
                
                // Connection status callbacks
                callbacks.onConnect = { [weak self] conversationId in
                    guard let self = self else { return }
                    print("🟢 ElevenLabs connected with \(agentType.displayName) - conversation ID: \(conversationId)")
                    DispatchQueue.main.async {
                        self.status = .connected
                        self.isSessionActive = true
                        
                        // Notify if exercise coach is ready
                        if agentType == .exerciseCoach {
                            NotificationCenter.default.post(
                                name: VoiceManager.exerciseCoachReadyNotification,
                                object: nil
                            )
                        }
                    }
                }
                
                callbacks.onDisconnect = { [weak self] in
                    guard let self = self else { return }
                    print("🔴 ElevenLabs \(agentType.displayName) disconnected")
                    DispatchQueue.main.async {
                        self.status = .disconnected
                        self.isSessionActive = false
                        // Reset the flag when disconnected
                        self.sessionRequestFlags[agentType] = false
                    }
                }
                
                // Mode change callback (speaking/listening)
                callbacks.onModeChange = { [weak self] newMode in
                    guard let self = self else { return }
                    print("🔄 ElevenLabs \(agentType.displayName) mode changed to: \(newMode)")
                    DispatchQueue.main.async {
                        self.mode = newMode
                        self.isSpeaking = (newMode == .speaking)
                        self.isListening = (newMode == .listening)
                    }
                }
                
                // Audio level updates
                callbacks.onVolumeUpdate = { [weak self] newVolume in
                    DispatchQueue.main.async {
                        self?.audioLevel = newVolume
                    }
                }
                
                // Message transcripts
                callbacks.onMessage = { [weak self] message, role in
                    guard let self = self else { return }
                    print("📝 ElevenLabs \(agentType.displayName) message (\(role.rawValue)): \(message)")
                    
                    // Try to extract JSON from the message if in onboarding mode
                    if agentType == .onboarding {
                        self.tryExtractJson(from: message)
                    }
                    
                    DispatchQueue.main.async {
                        if role == .user {
                            self.transcribedText = message
                        } else if role == .ai {
                            self.lastSpokenText = message
                        }
                    }
                }
                
                // Error handling
                callbacks.onError = { [weak self] error, details in
                    guard let self = self else { return }
                    print("⚠️ ElevenLabs \(agentType.displayName) error: \(error)")
                    print("⚠️ Error details: \(String(describing: details))")
                    
                    DispatchQueue.main.async {
                        self.voiceError = "ElevenLabs error: \(error)"
                        self.isSessionActive = false
                        
                        // Reset the session flag for definitive errors
                        if error != "WebSocket error" {
                            self.sessionRequestFlags[agentType] = false
                        }
                    }
                    
                    // If socket error, attempt reconnection
                    if error == "WebSocket error" {
                        self.handleConnectionFailure(agentType: agentType)
                    }
                }
                
                // Set status to connecting
                DispatchQueue.main.async {
                    self.status = .connecting
                }
                
                // Start the conversation session
                print("🚀 Attempting to start ElevenLabs \(agentType.displayName) session...")
                
                // Check if we should abort
                if sessionRequestFlags[agentType] != true {
                    print("⚠️ Session start was canceled before initialization")
                    throw NSError(domain: "VoiceManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session start canceled"])
                }
                
                conversation = try await ElevenLabsSDK.Conversation.startSession(
                    config: config,
                    callbacks: callbacks,
                    clientTools: clientTools
                )
                
                DispatchQueue.main.async {
                    self.isListening = true
                    self.isSessionActive = true
                    
                    print("✅ ElevenLabs \(agentType.displayName) session started successfully")
                    
                    // Mark operation as complete
                    self.sessionOperationInProgress = false
                    completion()
                    self.completeSessionOperation()
                }
                
            } catch {
                print("❌ Failed to start ElevenLabs \(agentType.displayName) conversation: \(error)")
                
                DispatchQueue.main.async {
                    self.voiceError = "Failed to start ElevenLabs: \(error.localizedDescription)"
                    self.status = .disconnected
                    self.isSessionActive = false
                    self.sessionRequestFlags[agentType] = false
                    
                    // Mark operation as complete
                    self.sessionOperationInProgress = false
                    completion()
                    self.completeSessionOperation()
                }
            }
        }
    }

    // Properly configure audio session for ElevenLabs with critical section protection
    private func configureAudioSessionForElevenLabs() async {
        // Use a critical section approach for audio configuration
        await withCheckedContinuation { continuation in
            sessionLock.lock()
            
            // Check if audio is already being configured
            if isConfiguringAudio {
                print("⚠️ Audio session already being configured, waiting...")
                sessionLock.unlock()
                
                // Poll until configuration is complete
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    Task { [weak self] in
                        await self?.configureAudioSessionForElevenLabs()
                        continuation.resume()
                    }
                }
                return
            }
            
            // Mark as configuring
            isConfiguringAudio = true
            sessionLock.unlock()
            
            // Configure audio session
            do {
                // First deactivate any existing audio session
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                
                // Configure with appropriate settings for ElevenLabs
                try audioSession.setCategory(.playAndRecord,
                                          mode: .spokenAudio,
                                          options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                
                // Set preferred audio session configuration
                try audioSession.setPreferredSampleRate(48000.0)
                try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer
                
                // Activate the session
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                
                print("✅ Audio session configured for ElevenLabs")
            } catch {
                print("❌ Audio session setup error: \(error)")
            }
            
            // Mark configuration as complete
            sessionLock.lock()
            isConfiguringAudio = false
            sessionLock.unlock()
            
            continuation.resume()
        }
    }

    // Update the startExerciseCoachAgent method to use completion handlers
    func startExerciseCoachAgent(completion: (() -> Void)? = nil) {
        print("🔍 startExerciseCoachAgent called")
        
        sessionLock.lock()
        
        // First ensure any existing session is fully terminated
        let needsTermination = isSessionActive
        sessionLock.unlock()
        
        if needsTermination {
            print("⚠️ Existing session active - ending it first")
            endElevenLabsSession { [weak self] in
                guard let self = self else { return }
                
                // Add a delay to ensure cleanup is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.startElevenLabsSession(agentType: .exerciseCoach, completion: completion)
                }
            }
        } else {
            startElevenLabsSession(agentType: .exerciseCoach, completion: completion)
        }
    }
    
    // Register tools specific to the onboarding agent
    private func registerOnboardingTools(clientTools: inout ElevenLabsSDK.ClientTools) {
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
            
            // Mark onboarding as completed
            UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
            
            // Update published property on main thread
            DispatchQueue.main.async {
                self.patientId = patientId
                self.hasCompletedOnboarding = true
                
                // Post notification for other parts of the app
                NotificationCenter.default.post(
                    name: VoiceManager.patientIdReceivedNotification,
                    object: nil,
                    userInfo: ["patient_id": patientId]
                )
                
                // Post notification that onboarding is complete
                NotificationCenter.default.post(
                    name: VoiceManager.onboardingCompletedNotification,
                    object: nil
                )
                
                // Automatically generate exercises with the new patient ID
                self.generateExercises(patientId: patientId)
            }
            
            print("✅ Saved patient ID: \(patientId)")
            return "Patient data saved successfully with ID: \(patientId)"
        }
        
        // Debug tool to log any message
        clientTools.register("logMessage") { parameters in
            guard let message = parameters["message"] as? String else {
                throw ElevenLabsSDK.ClientToolError.invalidParameters
            }
            
            print("🔵 ElevenLabs onboarding logMessage: \(message)")
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
                    
                    // Mark onboarding as completed
                    UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                    
                    DispatchQueue.main.async {
                        self.patientId = patientId
                        self.hasCompletedOnboarding = true
                        
                        // Post notification
                        NotificationCenter.default.post(
                            name: VoiceManager.patientIdReceivedNotification,
                            object: nil,
                            userInfo: ["patient_id": patientId]
                        )
                        
                        // Automatically generate exercises with the new patient ID
                        self.generateExercises(patientId: patientId)
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
        
        print("⭐️ Registered onboarding client tools: savePatientData, logMessage, saveJsonData")
    }
    
    // Register tools specific to the exercise coach agent
    private func registerExerciseCoachTools(clientTools: inout ElevenLabsSDK.ClientTools) {
        // Tool to log exercise progress
        clientTools.register("logExerciseProgress") { [weak self] parameters in
            guard let self = self else { return "Manager not available" }
            
            print("🔵 logExerciseProgress tool called with parameters: \(parameters)")
            
            guard let exerciseId = parameters["exercise_id"] as? String,
                  let progress = parameters["progress"] as? Double else {
                throw ElevenLabsSDK.ClientToolError.invalidParameters
            }
            
            // Here you would log this to your backend or local storage
            print("📊 Exercise Progress: \(exerciseId) - \(progress)%")
            
            return "Exercise progress logged successfully"
        }
        
        // Tool to provide exercise feedback
        clientTools.register("provideExerciseFeedback") { parameters in
            guard let feedbackType = parameters["type"] as? String,
                  let message = parameters["message"] as? String else {
                throw ElevenLabsSDK.ClientToolError.invalidParameters
            }
            
            print("🔵 Exercise Feedback (\(feedbackType)): \(message)")
            
            // Post notification with feedback information
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("ExerciseFeedback"),
                    object: nil,
                    userInfo: [
                        "type": feedbackType,
                        "message": message
                    ]
                )
            }
            
            return "Feedback provided successfully"
        }
        
        // Debug tool to log any message
        clientTools.register("logMessage") { parameters in
            guard let message = parameters["message"] as? String else {
                throw ElevenLabsSDK.ClientToolError.invalidParameters
            }
            
            print("🔵 ElevenLabs exercise coach logMessage: \(message)")
            return "Logged: \(message)"
        }
        
        print("⭐️ Registered exercise coach client tools: logExerciseProgress, provideExerciseFeedback, logMessage")
    }
    
    // Generate exercises for the patient
    func generateExercises(patientId: String) {
        DispatchQueue.main.async {
            self.isGeneratingExercises = true
        }
        
        print("🏋️‍♀️ Generating exercises for patient ID: \(patientId)")
        
        // Create URL request
        guard let url = URL(string: generateExercisesEndpoint) else {
            print("❌ Invalid generate exercises URL")
            DispatchQueue.main.async {
                self.isGeneratingExercises = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create request body
        let requestBody: [String: Any] = [
            "patient_id": patientId,
            "llm_provider": "openai"  // Can also use Claude
        ]
        
        // Convert to JSON data
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to serialize exercise generation request")
            DispatchQueue.main.async {
                self.isGeneratingExercises = false
            }
            return
        }
        
        request.httpBody = httpBody
        
        // Make API call
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Exercise generation error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isGeneratingExercises = false
                }
                return
            }
            
            // Log HTTP response for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 Exercise generation HTTP status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("❌ No data received from exercise generation API")
                DispatchQueue.main.async {
                    self.isGeneratingExercises = false
                }
                return
            }
            
            // Log raw response for debugging
            print("📊 Exercise generation raw response: \(String(data: data, encoding: .utf8) ?? "unable to decode")")
            
            do {
                // Parse response
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("📊 Exercise generation response: \(json ?? [:])")
                
                if let status = json?["status"] as? String, status == "success",
                   let exercisesJson = json?["exercises"] as? [[String: Any]] {
                    
                    // Store exercises in UserDefaults
                    if let exercisesData = try? JSONSerialization.data(withJSONObject: exercisesJson) {
                        UserDefaults.standard.set(exercisesData, forKey: "PatientExercises")
                        
                        DispatchQueue.main.async {
                            self.isGeneratingExercises = false
                            self.exercisesGenerated = true
                            
                            // Post notification that exercises are ready
                            NotificationCenter.default.post(
                                name: VoiceManager.exercisesGeneratedNotification,
                                object: nil,
                                userInfo: ["exercises_count": exercisesJson.count]
                            )
                        }
                        
                        print("✅ Generated \(exercisesJson.count) exercises and saved to UserDefaults")
                    }
                } else {
                    print("❌ Invalid exercise generation response format")
                    DispatchQueue.main.async {
                        self.isGeneratingExercises = false
                    }
                }
            } catch {
                print("❌ Failed to parse exercise generation response: \(error)")
                DispatchQueue.main.async {
                    self.isGeneratingExercises = false
                }
            }
        }
        
        task.resume()
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
                            
                            // Mark onboarding as completed
                            UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                            
                            DispatchQueue.main.async {
                                self.patientId = patientId
                                self.hasCompletedOnboarding = true
                                
                                // Post notification
                                NotificationCenter.default.post(
                                    name: VoiceManager.patientIdReceivedNotification,
                                    object: nil,
                                    userInfo: ["patient_id": patientId]
                                )
                                
                                // Automatically generate exercises
                                self.generateExercises(patientId: patientId)
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
                    
                    // Mark onboarding as completed
                    UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                    
                    DispatchQueue.main.async {
                        self.patientId = patientId
                        self.hasCompletedOnboarding = true
                        
                        // Post notification
                        NotificationCenter.default.post(
                            name: VoiceManager.patientIdReceivedNotification,
                            object: nil,
                            userInfo: ["patient_id": patientId]
                        )
                        
                        // Automatically generate exercises
                        self.generateExercises(patientId: patientId)
                    }
                }
            }
        }
    }
    
    // Reconnection logic
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    
    private func handleConnectionFailure(agentType: AgentType) {
        guard reconnectAttempt < maxReconnectAttempts else {
            print("⚠️ Maximum reconnection attempts reached")
            reconnectAttempt = 0
            sessionRequestFlags[agentType] = false // Reset flag after max attempts
            return
        }
        
        // For onboarding, don't attempt reconnect if onboarding is already completed
        if agentType == .onboarding && hasCompletedOnboarding {
            print("⚠️ Onboarding already completed, not attempting reconnection")
            sessionRequestFlags[agentType] = false
            return
        }
        
        let delay = pow(2.0, Double(reconnectAttempt)) // Exponential backoff
        reconnectAttempt += 1
        
        print("🔄 Attempting to reconnect \(agentType.displayName) in \(delay) seconds (attempt \(reconnectAttempt))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            // Check if session is still marked as requested
            self.sessionLock.lock()
            let shouldReconnect = self.sessionRequestFlags[agentType] == true && !self.isSessionActive
            self.sessionLock.unlock()
            
            if shouldReconnect {
                // Reset session request flag before attempting reconnect to prevent duplicate requests
                self.sessionRequestFlags[agentType] = false
                self.startElevenLabsSession(agentType: agentType)
            }
        }
    }
    
    // Start the onboarding agent specifically
    func startOnboardingAgent() {
        print("🔍 startOnboardingAgent called from: \(Thread.callStackSymbols)")
        
        // Extra guard to prevent starting if onboarding is complete or already in LandingView
        guard !hasCompletedOnboarding else {
            print("⛔️ Not starting onboarding agent - onboarding already completed")
            return
        }
        
        // Check if we're in the main app flow (not onboarding)
        if UserDefaults.standard.bool(forKey: "HasCompletedOnboarding") {
            print("⛔️ Not starting onboarding agent - user already in main app flow")
            return
        }
        
        startElevenLabsSession(agentType: .onboarding)
    }
    
    // Start the exercise coach agent specifically with optional completion
    func startExerciseCoachAgent() {
        startElevenLabsSession(agentType: .exerciseCoach)
    }
    
    // End the ElevenLabs conversation session with proper cleanup
    func endElevenLabsSession(completion: (() -> Void)? = nil) {
        sessionLock.lock()
        
        // Check if we're already cleaning up
        if isPerformingCleanup {
            print("⚠️ Already performing session cleanup - aborting duplicate request")
            sessionLock.unlock()
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        // Check if there's an active session
        guard isSessionActive || conversation != nil else {
            print("No active ElevenLabs session to end")
            sessionLock.unlock()
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        // Mark cleanup as in progress
        isPerformingCleanup = true
        sessionOperationInProgress = true
        
        // Store the current agent type for logging
        let currentAgentTypeForLog = currentAgentType
        sessionLock.unlock()
        
        print("Ending ElevenLabs \(currentAgentTypeForLog?.displayName ?? "Unknown") session")
        
        Task {
            do {
                // End the conversation session if it exists
                if let conversation = self.conversation {
                    try await conversation.endSession()
                }
                
                // Add a delay to ensure session cleanup is complete
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Deactivate audio session with delay to avoid conflicts
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second additional delay
                do {
                    try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                    print("Audio session deactivated successfully")
                } catch {
                    print("Failed to deactivate audio session: \(error)")
                }
                
                // Update state on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Reset all relevant state
                    self.conversation = nil
                    self.status = .disconnected
                    self.isListening = false
                    self.isSpeaking = false
                    self.isSessionActive = false
                    
                    // Reset all session flags to ensure clean state
                    for agentType in [AgentType.onboarding, AgentType.exerciseCoach] {
                        self.sessionRequestFlags[agentType] = false
                    }
                    
                    print("ElevenLabs \(currentAgentTypeForLog?.displayName ?? "Unknown") session ended")
                    
                    // Mark cleanup as complete
                    self.isPerformingCleanup = false
                    self.sessionOperationInProgress = false
                    
                    // Execute completion handler
                    completion?()
                    
                    // Process any queued operations
                    self.completeSessionOperation()
                }
                
            } catch {
                print("Error ending ElevenLabs session: \(error)")
                
                // Still need to clean up state even after error
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Reset all state after failure
                    self.conversation = nil
                    self.status = .disconnected
                    self.isListening = false
                    self.isSpeaking = false
                    self.isSessionActive = false
                    
                    // Reset all flags
                    for agentType in [AgentType.onboarding, AgentType.exerciseCoach] {
                        self.sessionRequestFlags[agentType] = false
                    }
                    
                    // Mark cleanup as complete
                    self.isPerformingCleanup = false
                    self.sessionOperationInProgress = false
                    
                    // Execute completion handler
                    completion?()
                    
                    // Process any queued operations
                    self.completeSessionOperation()
                }
            }
        }
    }
    
    // Speak text using the system's speech synthesizer
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        lastSpokenText = text
        self.completionHandler = completion
        
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
            
            // Reset all session request flags
            for agentType in [AgentType.onboarding, AgentType.exerciseCoach] {
                self.sessionRequestFlags[agentType] = false
            }
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
