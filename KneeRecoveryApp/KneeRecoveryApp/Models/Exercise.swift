import Foundation

struct Exercise: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let imageURL: URL?
    let duration: TimeInterval
    let targetJoints: [BodyJointType]
    let instructions: [String]
    
    init(id: UUID = UUID(), name: String, description: String,
         imageURLString: String? = nil, duration: TimeInterval = 180,
         targetJoints: [BodyJointType] = [], instructions: [String] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.imageURL = imageURLString != nil ? URL(string: imageURLString!) : nil
        self.duration = duration
        self.targetJoints = targetJoints
        self.instructions = instructions
    }
}

// Example exercises
extension Exercise {
    static let examples = [
        Exercise(
            name: "Knee Flexion",
            description: "Gently bend and extend your knee to improve range of motion",
            imageURLString: "https://example.com/knee-flexion.jpg",
            targetJoints: [.rightKnee, .rightAnkle, .rightHip],
            instructions: [
                "Sit on a chair with your feet flat on the floor",
                "Slowly lift your right foot and bend your knee",
                "Hold for 5 seconds",
                "Slowly lower your foot back to the floor",
                "Repeat 10 times"
            ]
        ),
        Exercise(
            name: "Straight Leg Raises",
            description: "Strengthen the quadriceps without bending the knee",
            imageURLString: "https://example.com/leg-raises.jpg",
            targetJoints: [.leftHip, .leftKnee, .leftAnkle],
            instructions: [
                "Lie on your back with one leg bent and one leg straight",
                "Tighten the thigh muscles of your straight leg",
                "Slowly lift your straight leg up about 12 inches",
                "Hold for 5 seconds",
                "Slowly lower your leg back down",
                "Repeat 10 times"
            ]
        ),
        Exercise(
            name: "Hamstring Stretch",
            description: "Stretch the back of your thigh to improve knee mobility",
            imageURLString: "https://example.com/hamstring-stretch.jpg",
            targetJoints: [.rightHip, .rightKnee, .rightAnkle],
            instructions: [
                "Sit on the edge of a chair",
                "Extend one leg forward with your heel on the floor",
                "Sit up straight and lean forward slightly at your hips",
                "Hold for 30 seconds",
                "Repeat with the other leg"
            ]
        )
    ]
}
