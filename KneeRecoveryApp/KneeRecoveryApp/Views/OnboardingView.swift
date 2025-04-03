import SwiftUI
import AVFoundation

struct OnboardingView: View {
    // State for animation and conversation
    @State private var animationState: AnimationState = .idle
    @State private var messages: [ConversationMessage] = []
    @State private var isOnboardingComplete = false
    @State private var patientId: String? = nil
    @State private var isLoading = false
    @State private var hasStartedAgent = false
    
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
            // Set up notification observers
            setupNotificationObservers()
            
            // Configure audio session to use speaker
            configureAudioSession()
            
            // Start the ElevenLabs onboarding agent only if not already started
            if !hasStartedAgent && !voiceManager.hasCompletedOnboarding {
                hasStartedAgent = true
                voiceManager.startOnboardingAgent()
                print("Called voiceManager.startOnboardingAgent()")
            }
            
            // Start with initial greeting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                animationState = .speaking
            }
        }
        .onDisappear {
            // Clean up notification observers
            removeNotificationObservers()
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
        .onChange(of: voiceManager.hasCompletedOnboarding) { _, completed in
            if completed && !isOnboardingComplete {
                handleOnboardingComplete()
            }
        }
        .onChange(of: isOnboardingComplete) { _, newValue in
            if newValue {
                // Ensure we don't restart the agent even if view reappears
                hasStartedAgent = true
                
                // Double check that session is terminated
                if voiceManager.isSessionActive {
                    voiceManager.endElevenLabsSession()
                }
            }
        }
        .navigationDestination(isPresented: $isOnboardingComplete) {
            LandingView()
                .environmentObject(voiceManager)
                .environmentObject(resourceCoordinator)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupNotificationObservers() {
        // Listen for when patient ID is received
        NotificationCenter.default.addObserver(
            forName: VoiceManager.patientIdReceivedNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let patientId = notification.userInfo?["patient_id"] as? String {
                self.patientId = patientId
                animationState = .thinking
                addMessage(text: "Thanks for sharing that information. I'm generating personalized exercises for you now...", isUser: false)
            }
        }
        
        // Listen for when exercises are generated
        NotificationCenter.default.addObserver(
            forName: VoiceManager.exercisesGeneratedNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleExercisesGenerated()
        }
        
        // Listen for when onboarding is completed
        NotificationCenter.default.addObserver(
            forName: VoiceManager.onboardingCompletedNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleOnboardingComplete()
        }
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self, name: VoiceManager.patientIdReceivedNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: VoiceManager.exercisesGeneratedNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: VoiceManager.onboardingCompletedNotification, object: nil)
    }
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func addMessage(text: String, isUser: Bool) {
        print("Adding message: \(text), isUser: \(isUser)")
        let message = ConversationMessage(text: text, isUser: isUser)
        messages.append(message)
        
        //设置成扬声器播放
        do{
          try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        }
        catch {
           
        }

        print("Messages count: \(messages.count)")
    }
    
    private func handleExercisesGenerated() {
        isLoading = false
        addMessage(text: "Your personalized exercises are ready! Let's get started with your knee recovery journey.", isUser: false)
        
        // Wait a moment to show the message before proceeding
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            handleOnboardingComplete()
        }
    }
    
    private func handleOnboardingComplete() {
        guard !isOnboardingComplete else { return }
        
        print("Onboarding complete, ending onboarding agent session and transitioning to Landing View")
        
        // End the ElevenLabs session
        voiceManager.endElevenLabsSession()
        
        // Small delay to allow session to properly end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Mark onboarding as complete in UserDefaults
            UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
            
            // Set state to navigate
            isOnboardingComplete = true
        }
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
