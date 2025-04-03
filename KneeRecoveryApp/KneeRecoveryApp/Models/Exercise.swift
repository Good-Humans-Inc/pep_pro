import Foundation

struct Exercise: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let imageURL: URL?
    let imageURL1: URL?
    let duration: TimeInterval
    let targetJoints: [BodyJointType]
    let instructions: [String]
    let firestoreId: String?
    let videoId: String?
    
    init(id: UUID = UUID(), name: String, description: String,
         imageURLString: String? = nil, imageURLString1: String? = nil, duration: TimeInterval = 180,
         targetJoints: [BodyJointType] = [], instructions: [String] = [],
         firestoreId: String? = nil,videoId:String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.imageURL = imageURLString != nil ? URL(string: imageURLString!) : nil
        self.imageURL1 = imageURLString1 != nil ? URL(string: imageURLString1!) : nil
        self.duration = duration
        self.targetJoints = targetJoints
        self.instructions = instructions
        self.firestoreId = firestoreId
        self.videoId = videoId
    }
}

// Example exercises
extension Exercise {
    static var examples = [
        Exercise(
            name: "Knee Flexion",
            description: "Gently bend and extend your knee to improve range of motion",
            imageURLString: "https://cdn1.newyorkhipknee.com/wp-content/uploads/2022/10/image2-6.jpg",
            imageURLString1: "https://cdn1.newyorkhipknee.com/wp-content/uploads/2022/10/image2-6.jpg",
            targetJoints: [Joint.rightKnee, Joint.rightAnkle, Joint.rightHip],
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
            imageURLString: "https://rehab2perform.com/wp-content/uploads/2022/02/single-leg.jpg",
            imageURLString1: "https://rehab2perform.com/wp-content/uploads/2022/02/single-leg.jpg",
            targetJoints: [Joint.leftHip, Joint.leftKnee, Joint.leftAnkle],
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
            imageURLString: "https://www.verywellfit.com/thmb/LJe06ZXW2XQ7HJiRZJ6eqO0xTLk=/750x0/filters:no_upscale():max_bytes(150000):strip_icc():format(webp)/TheSimpleHamstringStretch_annotated2-b28329393a9e4d828b93209db3729664.jpg",
            imageURLString1: "https://www.verywellfit.com/thmb/LJe06ZXW2XQ7HJiRZJ6eqO0xTLk=/750x0/filters:no_upscale():max_bytes(150000):strip_icc():format(webp)/TheSimpleHamstringStretch_annotated2-b28329393a9e4d828b93209db3729664.jpg",
            targetJoints: [Joint.rightHip, Joint.rightKnee, Joint.rightAnkle],
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

