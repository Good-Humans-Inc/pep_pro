import SwiftUI
import AVFoundation

struct OnboardingView: View {
    // State for animation and conversation
    @State private var animationState: AnimationState = .idle
    @State private var messages: [ConversationMessage] = []
    @State private var isOnboardingComplete = false
    
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
            let audioSession = AVAudioSession.sharedInstance()
            // Set the category with speaker option
            try audioSession.setCategory(.playAndRecord,
                                      mode: .spokenAudio,
                                      options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            
            // Activate the session
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Explicitly override the output to the speaker
            try audioSession.overrideOutputAudioPort(.speaker)
            
            print("Audio session configured to force speaker output")
            
            let currentRoute = audioSession.currentRoute
            for output in currentRoute.outputs {
                print("Audio output port: \(output.portType), name: \(output.portName)")
            }
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    private func addMessage(text: String, isUser: Bool) {
        let message = ConversationMessage(text: text, isUser: isUser)
        messages.append(message)
        
        // Check for completion cues in AI messages
        if !isUser {
            if text.contains("Let's get to work") ||
               text.contains("line up some") ||
               text.contains("make that slam dunk dream a reality") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    completeOnboarding()
                }
            }
        }
    }
    
    private func completeOnboarding() {
        // Save any data if needed
        
        // Navigate to main app
        isOnboardingComplete = true
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
