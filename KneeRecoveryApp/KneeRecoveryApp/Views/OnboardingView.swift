import SwiftUI
import Combine

struct OnboardingView: View {
    @EnvironmentObject private var voiceManager: VoiceManager
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    @State private var isOnboardingComplete = false
    @State private var userName: String = ""
    @State private var userPainPoints: [String] = []
    @State private var recommendedExercises: [Exercise] = []
    @State private var animationState: AnimationState = .idle
    @State private var conversationText: String = "Hi there! I'm your knee recovery assistant. What's your name?"
    
    enum AnimationState {
        case idle, listening, speaking, thinking
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Header
                Text("Welcome to Knee Recovery")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 30)
                
                Spacer()
                
                // Use the updated DogAnimation component with GIFs
                DogAnimation(state: $animationState)
                    .frame(width: 300, height: 300)
                
                // Conversation text
                Text(conversationText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                
                // User speech text if available
                if !voiceManager.transcribedText.isEmpty {
                    Text("You: \(voiceManager.transcribedText)")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                
                // Voice activity indicator
                HStack {
                    Circle()
                        .fill(voiceManager.isListening ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    
                    Text(voiceManager.isListening ? "Listening..." : (voiceManager.isSpeaking ? "Speaking..." : "Tap to start"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 5)
                
                Spacer()
                
                // Skip button
                Button(action: {
                    completeOnboarding()
                }) {
                    Text("Skip onboarding")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .padding()
                }
            }
        }
        .onAppear {
            startOnboarding()
        }
        .onChange(of: voiceManager.transcribedText) { oldValue, newValue in
            handleUserSpeech(newValue)
        }
        .onChange(of: voiceManager.isSpeaking) { oldValue, newValue in
            animationState = newValue ? .speaking : .listening
        }
        .onChange(of: voiceManager.isListening) { oldValue, newValue in
            if newValue && !voiceManager.isSpeaking {
                animationState = .listening
            }
        }
        .navigationDestination(isPresented: $isOnboardingComplete) {
            LandingView()
                .environmentObject(voiceManager)
                .environmentObject(resourceCoordinator)
        }
    }
    
    private func startOnboarding() {
        // Start the ElevenLabs session
        voiceManager.startElevenLabsSession()
        
        // The voice agent will automatically start the conversation
        // through the callbacks set up in VoiceManager
        
        // We'll update conversationText based on the lastSpokenText from the agent
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            animationState = .speaking
            
            // If the agent doesn't speak automatically, start with a greeting
            if voiceManager.lastSpokenText.isEmpty {
                voiceManager.speak("Hi there! I'm your knee recovery assistant. What's your name?")
            }
        }
    }
    
    private func handleUserSpeech(_ speech: String) {
        // Process user responses based on the current state of conversation
        if userName.isEmpty {
            // Extract name from user speech
            let namePattern = "(?:I'm|I am|My name is|name's|this is|call me) (\\w+)"
            if let match = speech.range(of: namePattern, options: .regularExpression) {
                let fullMatch = String(speech[match])
                let components = fullMatch.components(separatedBy: " ")
                if components.count > 1 {
                    userName = components.last ?? ""
                    
                    // Move to the next question after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        animationState = .speaking
                        conversationText = "Nice to meet you, \(userName)! Can you tell me about your knee pain? Where does it hurt and what activities cause discomfort?"
                    }
                }
            } else if !speech.isEmpty {
                // Assume the first response is the name
                userName = speech
                
                // Move to the next question
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    animationState = .speaking
                    conversationText = "Nice to meet you, \(userName)! Can you tell me about your knee pain? Where does it hurt and what activities cause discomfort?"
                }
            }
        } else if userPainPoints.isEmpty {
            // Store pain point information
            if !speech.isEmpty {
                userPainPoints.append(speech)
                
                // Simulate sending data to server and getting recommendations
                animationState = .thinking
                conversationText = "Thanks for sharing that. Let me analyze your situation and recommend some exercises..."
                
                // Simulate server delay and response
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    // Generate recommended exercises based on pain points
                    recommendedExercises = generateRecommendedExercises(from: speech)
                    
                    // Update the conversation
                    animationState = .speaking
                    conversationText = "Based on what you've told me, I've prepared a set of exercises that should help with your knee recovery. Let's get started!"
                    
                    // Complete onboarding after a delay to allow the user to hear the final message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        completeOnboarding()
                    }
                }
            }
        }
    }
    
    private func generateRecommendedExercises(from painDescription: String) -> [Exercise] {
        // In a real app, this would come from your server
        // For now, we'll create exercises based on keywords in the pain description
        
        var exercises: [Exercise] = []
        
        // Check for common knee pain issues in the description
        let lowerDescription = painDescription.lowercased()
        
        if lowerDescription.contains("stair") || lowerDescription.contains("step") {
            exercises.append(Exercise(
                name: "Step-Ups",
                description: "Strengthen your knee by stepping up and down a step",
                targetJoints: [.leftKnee, .rightKnee],
                instructions: [
                    "Stand in front of a step or sturdy platform",
                    "Step up with your affected leg",
                    "Bring your other foot up to join it",
                    "Step down with the affected leg first",
                    "Repeat 10 times, then switch legs"
                ]
            ))
        }
        
        if lowerDescription.contains("stiff") || lowerDescription.contains("flexib") {
            exercises.append(Exercise(
                name: "Knee Flexion",
                description: "Improve flexibility and range of motion in your knee",
                targetJoints: [.leftKnee, .rightKnee],
                instructions: [
                    "Sit on a chair with feet flat on the floor",
                    "Slowly slide one foot back, bending your knee as much as comfortable",
                    "Hold for 5 seconds",
                    "Return to starting position",
                    "Repeat 10 times, then switch legs"
                ]
            ))
        }
        
        if lowerDescription.contains("weak") || lowerDescription.contains("strength") {
            exercises.append(Exercise(
                name: "Straight Leg Raises",
                description: "Strengthen the quadriceps without stressing the knee joint",
                targetJoints: [.leftHip, .leftKnee, .rightHip, .rightKnee],
                instructions: [
                    "Lie on your back with one leg bent and one leg straight",
                    "Tighten the thigh muscles of your straight leg",
                    "Lift the straight leg up about 12 inches",
                    "Hold for 5 seconds, then slowly lower",
                    "Repeat 10 times, then switch legs"
                ]
            ))
        }
        
        // Always include at least one basic exercise
        if exercises.isEmpty {
            exercises.append(Exercise(
                name: "Gentle Knee Bends",
                description: "A safe exercise for most knee conditions",
                targetJoints: [.leftKnee, .rightKnee],
                instructions: [
                    "Stand with feet shoulder-width apart",
                    "Hold onto a sturdy chair or counter for balance",
                    "Slowly bend your knees to a comfortable position",
                    "Hold for 5 seconds",
                    "Return to standing",
                    "Repeat 10 times"
                ]
            ))
        }
        
        return exercises
    }
    
    private func completeOnboarding() {
        // Save user data and recommended exercises
        saveUserData()
        
        // Navigate to the main app
        isOnboardingComplete = true
    }
    
    private func saveUserData() {
        // In a real app, you would persist this data
        // For now, we'll update the app's exercise list
        
        // Get the current exercises
        var allExercises = Exercise.examples
        
        // Add the recommended exercises
        allExercises.append(contentsOf: recommendedExercises)
        
        // Update the static examples with our new list
        Exercise.examples = allExercises
    }
}
