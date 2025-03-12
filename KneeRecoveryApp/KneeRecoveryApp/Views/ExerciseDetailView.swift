import SwiftUI
import AVFoundation

struct ExerciseDetailView: View {
    let exercise: Exercise
    
    @State private var isExerciseActive = false
    @State private var remainingTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var isPTEditMode = false
    @State private var showingPTModifySheet = false
    @State private var showingVideoRecorder = false
    
    // Exercise modification fields
    @State private var modifiedFrequency = "daily"
    @State private var modifiedSets = 3
    @State private var modifiedReps = 10
    @State private var modifiedNotes = ""
    @State private var recordedVideoURL: URL? = nil
    
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var visionManager: VisionManager
    @EnvironmentObject private var voiceManager: VoiceManager
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    
    var body: some View {
        ZStack {
            // Camera feed with body pose visualization overlay when exercise is active
            if isExerciseActive {
                ZStack {
                    // Camera view
                    CameraPreview(session: cameraManager.session)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Body pose overlay
                    BodyPoseView(bodyPose: visionManager.currentBodyPose)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Timer and controls overlay
                    VStack {
                        Spacer()
                        
                        // Timer display
                        Text(timeString(from: remainingTime))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(16)
                        
                        Spacer()
                        
                        // Stop button
                        Button(action: {
                            stopExercise()
                        }) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop Exercise")
                            }
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.bottom, 32)
                    }
                }
            } else {
                // Exercise details and start button when not active
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header with image
                        if let imageURL = exercise.imageURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .aspectRatio(16/9, contentMode: .fit)
                                        .overlay(ProgressView())
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(16/9, contentMode: .fit)
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .aspectRatio(16/9, contentMode: .fit)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.largeTitle)
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .cornerRadius(12)
                        }
                        
                        // Exercise title and description
                        Text(exercise.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(exercise.description)
                            .foregroundColor(.secondary)
                        
                        // Target joints
                        VStack(alignment: .leading) {
                            Text("Target Areas")
                                .font(.headline)
                            
                            HStack {
                                ForEach(exercise.targetJoints, id: \.self) { joint in
                                    Text(joint.rawValue)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        
                        // Instructions
                        VStack(alignment: .leading) {
                            Text("Instructions")
                                .font(.headline)
                            
                            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
                                HStack(alignment: .top) {
                                    Text("\(index + 1).")
                                        .fontWeight(.bold)
                                    Text(instruction)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        
                        // Start button
                        Button(action: {
                            startExercise()
                        }) {
                            Text("Start Exercise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.top, 16)
                    }
                    .padding()
                }
            }
        }
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarItems(trailing: isExerciseActive ? nil : Button(action: {
            // Info button action
        }) {
            Image(systemName: "info.circle")
        })
        .onDisappear {
            if isExerciseActive {
                stopExercise()
            }
        }
    }
    
    private func startExercise() {
        // Begin coordinating resources
        resourceCoordinator.printAudioRouteInfo() // Check what audio devices are connected
        resourceCoordinator.testMicrophoneInput() // Test if mic is receiving audio
        resourceCoordinator.startExerciseSession { success in
            guard success else { return }
            
            // Start camera and vision processing
            cameraManager.startSession()
            visionManager.startProcessing(cameraManager.videoOutput)
            
            // Start voice assistant
            //voiceManager.speak("Let's begin the \(exercise.name) exercise. I'll guide you through it.")
            voiceManager.startElevenLabsSession()
            
            // Start speech recognition
            speechRecognitionManager.startListening()
            
            // Setup timer
            remainingTime = exercise.duration
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if remainingTime > 0 {
                    remainingTime -= 1
                } else {
                    stopExercise()
                }
            }
            
            // Update UI
            isExerciseActive = true
        }
    }
    
    private func stopExercise() {
        // Stop timer
        timer?.invalidate()
        timer = nil
        
        // Stop coordinating resources
        resourceCoordinator.stopExerciseSession()
        
        // Update UI
        isExerciseActive = false
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Camera preview for AVCaptureSession
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
