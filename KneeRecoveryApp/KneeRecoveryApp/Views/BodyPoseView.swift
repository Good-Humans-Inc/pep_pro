import SwiftUI

struct BodyPoseView: View {
    @EnvironmentObject var visionManager: VisionManager
    
    // Constants for visualization
    private let jointRadius: CGFloat = 8
    private let connectionLineWidth: CGFloat = 3
    private let jointColor = Color.green
    private let connectionColor = Color.yellow
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw connections between joints
                ForEach(getValidConnections(), id: \.self) { connection in
                    Path { path in
                        guard let startJoint = visionManager.currentBodyPose.joints[connection.start],
                              let endJoint = visionManager.currentBodyPose.joints[connection.end] else {
                            return
                        }
                        
                        path.move(to: startJoint.position)
                        path.addLine(to: endJoint.position)
                    }
                    .stroke(connectionColor, lineWidth: connectionLineWidth)
                }
                
                // Draw joints
                ForEach(Array(visionManager.currentBodyPose.joints), id: \.key) { jointType, joint in
                    if joint.isValid {
                        Circle()
                            .fill(jointColor)
                            .frame(width: jointRadius * 2, height: jointRadius * 2)
                            .position(joint.position)
                    }
                }
            }
            .onAppear {
                visionManager.updatePreviewLayer(rect: geometry.frame(in: .local))
            }
            .onChange(of: geometry.size) { newSize in
                visionManager.updatePreviewLayer(rect: geometry.frame(in: .local))
            }
        }
    }
    
    // Define valid connections between joints
    private func getValidConnections() -> [JointConnection] {
        return [
            // Left arm
            JointConnection(start: .leftShoulder, end: .leftElbow),
            JointConnection(start: .leftElbow, end: .leftWrist),
            
            // Right arm
            JointConnection(start: .rightShoulder, end: .rightElbow),
            JointConnection(start: .rightElbow, end: .rightWrist),
            
            // Shoulders
            JointConnection(start: .leftShoulder, end: .rightShoulder),
            
            // Left leg
            JointConnection(start: .leftHip, end: .leftKnee),
            JointConnection(start: .leftKnee, end: .leftAnkle),
            
            // Right leg
            JointConnection(start: .rightHip, end: .rightKnee),
            JointConnection(start: .rightKnee, end: .rightAnkle),
            
            // Hips
            JointConnection(start: .leftHip, end: .rightHip),
            
            // Spine
            JointConnection(start: .leftShoulder, end: .leftHip),
            JointConnection(start: .rightShoulder, end: .rightHip)
        ]
    }
}

// Helper struct to define joint connections
struct JointConnection: Hashable {
    let start: BodyJointType
    let end: BodyJointType
}

#Preview {
    BodyPoseView()
        .environmentObject(VisionManager(appState: AppState()))
}
