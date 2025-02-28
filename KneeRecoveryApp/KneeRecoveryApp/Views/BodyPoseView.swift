import SwiftUI

struct BodyPoseView: View {
    let bodyPose: BodyPose
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw connections
                JointConnectionsView(connections: bodyPose.validConnections())
                
                // Draw joints
                ForEach(Array(bodyPose.joints.values.filter { $0.isValid }), id: \.id) { joint in
                    Circle()
                        .fill(jointColor(for: joint.id))
                        .frame(width: 12, height: 12)
                        .position(joint.position)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        )
                }
            }
        }
    }
    
    private func jointColor(for jointType: BodyJointType) -> Color {
        switch jointType {
        case .leftEye, .rightEye, .leftEar, .rightEar, .nose:
            return .yellow
        case .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return .green
        case .root, .leftHip, .rightHip:
            return .blue
        case .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
            return .red // Highlighting knee and ankle joints for knee exercises
        }
    }
}

struct JointConnectionsView: View {
    let connections: [(CGPoint, CGPoint)]
    
    var body: some View {
        Canvas { context, size in
            for connection in connections {
                let path = Path { p in
                    p.move(to: connection.0)
                    p.addLine(to: connection.1)
                }
                
                context.stroke(
                    path,
                    with: .color(.white),
                    lineWidth: 3
                )
            }
        }
    }
}

// For previews
extension BodyPose {
    static var preview: BodyPose {
        var pose = BodyPose()
        
        // Add some sample joints for preview
        let centerX: CGFloat = UIScreen.main.bounds.width / 2
        let centerY: CGFloat = UIScreen.main.bounds.height / 2
        
        // Head
        pose.joints[.nose] = BodyJoint(id: .nose, position: CGPoint(x: centerX, y: centerY - 100), confidence: 0.98)
        pose.joints[.leftEye] = BodyJoint(id: .leftEye, position: CGPoint(x: centerX - 15, y: centerY - 110), confidence: 0.97)
        pose.joints[.rightEye] = BodyJoint(id: .rightEye, position: CGPoint(x: centerX + 15, y: centerY - 110), confidence: 0.97)
        
        // Shoulders
        pose.joints[.leftShoulder] = BodyJoint(id: .leftShoulder, position: CGPoint(x: centerX - 50, y: centerY - 50), confidence: 0.95)
        pose.joints[.rightShoulder] = BodyJoint(id: .rightShoulder, position: CGPoint(x: centerX + 50, y: centerY - 50), confidence: 0.95)
        
        // Torso
        pose.joints[.leftHip] = BodyJoint(id: .leftHip, position: CGPoint(x: centerX - 40, y: centerY + 50), confidence: 0.9)
        pose.joints[.rightHip] = BodyJoint(id: .rightHip, position: CGPoint(x: centerX + 40, y: centerY + 50), confidence: 0.9)
        
        // Legs
        pose.joints[.leftKnee] = BodyJoint(id: .leftKnee, position: CGPoint(x: centerX - 35, y: centerY + 120), confidence: 0.85)
        pose.joints[.rightKnee] = BodyJoint(id: .rightKnee, position: CGPoint(x: centerX + 35, y: centerY + 120), confidence: 0.85)
        pose.joints[.leftAnkle] = BodyJoint(id: .leftAnkle, position: CGPoint(x: centerX - 30, y: centerY + 190), confidence: 0.8)
        pose.joints[.rightAnkle] = BodyJoint(id: .rightAnkle, position: CGPoint(x: centerX + 30, y: centerY + 190), confidence: 0.8)
        
        return pose
    }
}
