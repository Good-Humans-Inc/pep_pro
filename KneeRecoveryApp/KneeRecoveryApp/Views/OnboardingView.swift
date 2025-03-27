import SwiftUI
import AVFoundation

struct OnboardingView: View {
    // State for animation and conversation
    @State private var animationState: AnimationState = .idle
    @State private var messages: [ConversationMessage] = []
    @State private var isOnboardingComplete = false
    @State private var patientId: String? = nil
    @State private var isLoading = false
    
    // Scroll view proxy for auto-scrolling to latest message
    @State private var scrollProxy: ScrollViewProxy? = nil
    
    // Environment objects
    @EnvironmentObject private var voiceManager: VoiceManager
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    
    enum AnimationState {
        case idle, listening, speaking, thinking
    }
    
    struct ConversationMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isUser: Bool
        let timestamp = Date()
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Dog animation
                DogAnimation(state: $animationState)
                    .frame(width: 200, height: 200)
                
                // Conversation messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                ConversationBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .onAppear {
                        scrollProxy = proxy
                    }
                    .onChange(of: messages) { _, newMessages in
                        if let lastMessage = newMessages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Voice activity indicator
                HStack {
                    Circle()
                        .fill(animationState == .listening ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    
                    Text(animationState == .listening ? "Listening..." :
                         (animationState == .speaking ? "Speaking..." : "Tap to start"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 5)
                .padding(.bottom, 10)
                
                // Loading indicator
                if isLoading {
                    ProgressView("Processing...")
                        .padding()
                }
            }
            .padding()
        }
        .onAppear {
            // Configure audio session to use speaker
            configureAudioSession()
            
            // Start the ElevenLabs session
            voiceManager.startElevenLabsSession()
            print("Called voiceManager.startElevenLabsSession()")
            
            // Start with initial greeting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                animationState = .speaking
            }
        }
        .onChange(of: voiceManager.isSpeaking) { _, isSpeaking in
            animationState = isSpeaking ? .speaking : .listening
        }
        .onChange(of: voiceManager.isListening) { _, isListening in
            if isListening && !voiceManager.isSpeaking {
                animationState = .listening
            }
        }
        .onChange(of: voiceManager.lastSpokenText) { _, newText in
            if !newText.isEmpty {
                addMessage(text: newText, isUser: false)
                
                // Check if this message contains the patient_id from onboarding
                checkForPatientId(in: newText)
            }
        }
        .onChange(of: voiceManager.transcribedText) { _, newText in
            if !newText.isEmpty {
                addMessage(text: newText, isUser: true)
            }
        }
        .navigationDestination(isPresented: $isOnboardingComplete) {
            LandingView()
                .environmentObject(voiceManager)
                .environmentObject(resourceCoordinator)
        }
    }
    
    // MARK: - Helper Methods
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func addMessage(text: String, isUser: Bool) {
        let message = ConversationMessage(text: text, isUser: isUser)
        messages.append(message)
    }
    
    // Check for patient_id in the agent's response
    private func checkForPatientId(in text: String) {
        // Look for JSON-like content in the text
        if let range = text.range(of: "{.*\"patient_id\"\\s*:\\s*\"([^\"]+)\".*}", options: .regularExpression) {
            let jsonText = String(text[range])
            
            // Try to extract the patient_id using a more precise regex
            if let idRange = jsonText.range(of: "\"patient_id\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                let idText = String(jsonText[idRange])
                
                // Extract just the UUID part
                if let uuidRange = idText.range(of: "\"([^\"]+)\"", options: .regularExpression, range: idText.range(of: ":")!.upperBound..<idText.endIndex) {
                    let uuidWithQuotes = String(idText[uuidRange])
                    let uuid = uuidWithQuotes.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Store the patient_id
                    self.patientId = uuid
                    UserDefaults.standard.set(uuid, forKey: "PatientID")
                    print("Extracted patient UUID: \(uuid)")
                    
                    // Generate exercises with this ID
                    isLoading = true
                    generateExercises(for: uuid) { success in
                        DispatchQueue.main.async {
                            isLoading = false
                            if success {
                                isOnboardingComplete = true
                            } else {
                                // Show error message
                                addMessage(text: "I'm sorry, there was an error generating your exercises. Please try again.", isUser: false)
                            }
                        }
                    }
                }
            } else {
                // Alternative approach: try parsing as JSON
                do {
                    if let jsonData = jsonText.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let patientId = json["patient_id"] as? String {
                        
                        // Store the patient_id
                        self.patientId = patientId
                        UserDefaults.standard.set(patientId, forKey: "PatientID")
                        print("Extracted patient UUID from JSON: \(patientId)")
                        
                        // Generate exercises with this ID
                        isLoading = true
                        generateExercises(for: patientId) { success in
                            DispatchQueue.main.async {
                                isLoading = false
                                if success {
                                    isOnboardingComplete = true
                                } else {
                                    // Show error message
                                    addMessage(text: "I'm sorry, there was an error generating your exercises. Please try again.", isUser: false)
                                }
                            }
                        }
                    }
                } catch {
                    print("Error parsing JSON: \(error)")
                }
            }
        }
    }
    
    private func generateExercises(for patientId: String, completion: @escaping (Bool) -> Void) {
        // API endpoint
        guard let url = URL(string: "https://us-central1-knee-recovery-app.cloudfunctions.net/generate_exercises") else {
            completion(false)
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let requestBody: [String: Any] = [
            "patient_id": patientId,
            "llm_provider": "claude"  // or "openai" based on your preference
        ]
        
        // Convert data to JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error creating request body: \(error)")
            completion(false)
            return
        }
        
        // Make API call
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error generating exercises: \(error)")
                completion(false)
                return
            }
            
            guard let data = data else {
                print("No data received from exercise generation")
                completion(false)
                return
            }
            
            do {
                // Parse response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String,
                   status == "success" {
                    // Store exercises in UserDefaults or a dedicated service
                    if let exercisesData = try? JSONSerialization.data(withJSONObject: json["exercises"] ?? []) {
                        UserDefaults.standard.set(exercisesData, forKey: "PatientExercises")
                    }
                    completion(true)
                } else {
                    completion(false)
                }
            } catch {
                print("Error parsing exercise response: \(error)")
                completion(false)
            }
        }.resume()
    }
}

// Conversation bubble component
struct ConversationBubble: View {
    let message: OnboardingView.ConversationMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                    .multilineTextAlignment(message.isUser ? .trailing : .leading)
                
                Text(timeString(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }
            
            if !message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
