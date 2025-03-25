import SwiftUI
import SDWebImageSwiftUI

struct DogAnimation: View {
    @Binding var state: OnboardingView.AnimationState
    
    var body: some View {
        ZStack {
            // Idle state - hi.gif
            if state == .idle {
                AnimatedImage(name: "hi.gif")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            }
            
            // Speaking state - wagging.gif
            if state == .speaking {
                AnimatedImage(name: "wagging.gif")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            }
            
            // Listening state - custom ear animation or another gif
            if state == .listening {
                AnimatedImage(name: "hi.gif") // You could use a different gif for listening state
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
                    .overlay(
                        Image(systemName: "ear.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .offset(x: 40, y: -40)
                            .foregroundColor(.blue)
                            .opacity(0.8)
                            .scaleEffect(pulsingAnimation())
                    )
            }
            
            // Thinking state - encouraging.gif
            if state == .thinking {
                AnimatedImage(name: "encouraging.gif")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
    }
    
    // Animation for the pulsing effect
    private func pulsingAnimation() -> CGFloat {
        let animation = Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        return withAnimation(animation) {
            return 1.0 + 0.1 * sin(Date().timeIntervalSince1970 * 5)
        }
    }
}
