import SwiftUI
import AVFoundation

struct ExerciseDetailView: View {
    let exercise: Exercise
    
    // State variables
    @State private var isExerciseActive = false
    @State private var remainingTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var showingVideoRecorder = false
    @State private var showingModifySheet = false
    
    // Exercise modification fields
    @State private var modifiedFrequency = "daily"
    @State private var modifiedSets = 3
    @State private var modifiedReps = 10
    @State private var modifiedNotes = ""
    @State private var recordedVideoURL: URL? = nil
    
    // Exercise report states
    @State private var showingExerciseReport = false
    @State private var exerciseDuration: TimeInterval = 0
    
    // API connection states
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    
    // Coach state
    @State private var coachMessages: [String] = []
    @State private var showCoachFeedback = false
    
    // Operation tracking flags
    @State private var isStartingExercise = false
    @State private var isStoppingExercise = false
    @State private var isTransitioning = false
    @State private var hasCompletedFirstAppearance = false
    @State private var cameraStartupError = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    // Environment objects
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var visionManager: VisionManager
    @EnvironmentObject var voiceManager: VoiceManager
    @EnvironmentObject private var speechRecognitionManager: SpeechRecognitionManager
    @EnvironmentObject private var resourceCoordinator: ResourceCoordinator
    
    // App Storage for tracking first launch
    @AppStorage("hasStartedExerciseBefore") private var hasStartedExerciseBefore = false
    
    var body: some View {
        mainContentView
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(trailing: isExerciseActive ? nil : Button(action: {
                // Info button action
            }) {
                Image(systemName: "info.circle")
            })
            .onAppear {
                print("📱 ExerciseDetailView appeared")
                
                // Force reset all systems on first appearance
                if !hasCompletedFirstAppearance {
                    print("🔄 First appearance - forcing resource reset")
                    resetAllResources()
                    hasCompletedFirstAppearance = true
                }
                
                // Set up exercise coach notification observer
                setupExerciseCoachObserver()
                
                // Set up camera status observer
                setupCameraObserver()
            }
            .onDisappear {
                print("📴 ExerciseDetailView disappearing - Active: \(isExerciseActive), Starting: \(isStartingExercise), Transitioning: \(isTransitioning)")
                
                // Only clean up if we're not in the middle of starting
                if !isStartingExercise || isExerciseActive {
                    print("🧹 Cleaning up exercise resources")
                    
                    // Stop any active timers
                    timer?.invalidate()
                    timer = nil
                    
                    // Forcefully clear any active ElevenLabs sessions
                    voiceManager.endElevenLabsSession()
                    
                    // Clear camera resources
                    cameraManager.resetSession()
                    visionManager.stopProcessing()
                    
                    // Reset states
                    isExerciseActive = false
                    isStartingExercise = false
                    isStoppingExercise = false
                    isTransitioning = false
                    cameraStartupError = false
                } else {
                    print("⚠️ Skipping cleanup because exercise is still starting up")
                }
                
                // Additional cleanup
                speechRecognitionManager.stopListening()
                
                // Always deactivate audio session when leaving the view
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    print("🔇 Audio session deactivated")
                } catch {
                    print("❌ Error deactivating audio session: \(error)")
                }
                
                // Clean up notification observers
                removeExerciseCoachObserver()
                removeCameraObserver()
            }
            .sheet(isPresented: $showingModifySheet) {
                ModifyExerciseView(
                    exercise: exercise,
                    frequency: $modifiedFrequency,
                    sets: $modifiedSets,
                    reps: $modifiedReps,
                    notes: $modifiedNotes,
                    onSave: saveModifications
                )
            }
            .sheet(isPresented: $showingVideoRecorder) {
                ExerciseVideoRecorder(onVideoSaved: { url in
                    self.recordedVideoURL = url
                    saveModifications()
                })
            }
            // Use fullScreenCover for the report instead of sheet for better presentation
            .fullScreenCover(isPresented: $showingExerciseReport) {
                NavigationView {
                    ExerciseReportView(
                        exercise: exercise,
                        duration: exerciseDuration,
                        date: Date()
                    )
                    .environmentObject(voiceManager)
                    .navigationBarItems(trailing: Button("Done") {
                        showingExerciseReport = false
                    })
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Exercise Setup Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK")) {
                        // Reset states when error is acknowledged
                        isStartingExercise = false
                        isTransitioning = false
                        cameraStartupError = false
                    }
                )
            }
    }
    
    // Break down the main content view to help compiler with type checking
    private var mainContentView: some View {
        ZStack {
            // Camera feed with body pose visualization overlay when exercise is active
            if isExerciseActive {
                activeExerciseView
            } else {
                exerciseDetailsView
            }
            
            // Loading overlay when starting exercise
            if isStartingExercise {
                loadingOverlayView
            }
            
            // Upload overlay
            if isUploading {
                uploadOverlayView
            }
        }
    }
    
    // Active exercise view with camera feed
    private var activeExerciseView: some View {
        ZStack {
            // Camera view
            CameraPreview(session: cameraManager.session)
                .edgesIgnoringSafeArea(.all)
            
            // Body pose overlay
            BodyPoseView(bodyPose: visionManager.currentBodyPose)
                .edgesIgnoringSafeArea(.all)
            
            // Coach message bubble if there are messages
            if !coachMessages.isEmpty, showCoachFeedback {
                coachMessageView
            }
            
            // Timer and controls overlay
            exerciseControlsView
        }
    }
    
    // Coach message view
    private var coachMessageView: some View {
        VStack {
            Text(coachMessages.last ?? "")
                .padding()
                .background(Color.white.opacity(0.8))
                .foregroundColor(.black)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 40)
            
            Spacer()
        }
    }
    
    // Controls view for active exercise
    private var exerciseControlsView: some View {
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
            .disabled(isStoppingExercise)
        }
    }
    
    // Loading overlay view
    private var loadingOverlayView: some View {
        Color.black.opacity(0.7)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Setting up exercise...")
                        .foregroundColor(.white)
                        .padding(.top, 20)
                }
            )
    }
    
    // Upload progress overlay
    private var uploadOverlayView: some View {
        VStack {
            ProgressView()
            Text("Saving changes...")
                .font(.caption)
                .padding(.top, 8)
        }
        .frame(width: 150, height: 100)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(10)
    }
    
    // Exercise details view - shown when not in active exercise mode
    private var exerciseDetailsView: some View {
        let screenWidth = UIScreen.main.bounds.width
        
        return VStack(){
            YoutubePlayerView(videoID: exercise.videoId ?? "")
                         .frame(width: screenWidth, height: screenWidth * 9 / 16) // 计算16:9 高度
                         .background(Color.black)
                         .cornerRadius(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with image
//                    if let imageURL = exercise.imageURL1 {
//                        AsyncImage(url: imageURL) { phase in
//                            switch phase {
//                            case .empty:
//                                Rectangle()
//                                    .fill(Color.gray.opacity(0.2))
//                                    .aspectRatio(16/9, contentMode: .fit)
//                                    .overlay(ProgressView())
//                            case .success(let image):
//                                image
//                                    .resizable()
//                                    .aspectRatio(16/9, contentMode: .fit)
//                            case .failure:
//                                Rectangle()
//                                    .fill(Color.gray.opacity(0.2))
//                                    .aspectRatio(16/9, contentMode: .fit)
//                                    .overlay(
//                                        Image(systemName: "photo")
//                                            .font(.largeTitle)
//                                    )
//                            @unknown default:
//                                EmptyView()
//                            }
//                        }
//                        .cornerRadius(12)
//                    }
//
                    // Exercise title and description
                    Text(exercise.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(exercise.description)
                        .foregroundColor(.secondary)
                    
                    // Modification controls
                    exerciseModificationSection
                    
                    // Target joints section
                    targetJointsSection
                    
                    // Instructions section
                    instructionsSection
                    
                    // Start button
                    Button(action: {
                        startExercise()
                    }) {
                        Text("Start Exercise")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isStartingExercise ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.top, 16)
                    .disabled(isStartingExercise)
                }
                .padding()
            }
        }
    }
    
    // Modification section
    private var exerciseModificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Customize Exercise")
                .font(.headline)
                .foregroundColor(.blue)
            
            Button(action: {
                showingModifySheet = true
            }) {
                HStack {
                    Image(systemName: "pencil")
                    Text("Modify Exercise")
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button(action: {
                showingVideoRecorder = true
            }) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Record Custom Video")
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let error = uploadError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Divider()
        }
    }
    
    // Target joints section
    private var targetJointsSection: some View {
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
    }
    
    // Instructions section
    private var instructionsSection: some View {
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
    }
    
    // Force reset of all resources for first run
    private func resetAllResources() {
        print("♻️ Force resetting all resources")
        
        // End any existing voice sessions
        voiceManager.endElevenLabsSession()
        
        // Reset camera and vision systems
        cameraManager.resetSession()
        visionManager.stopProcessing()
        
        // Reset resource coordinator
        resourceCoordinator.stopExerciseSession()
        
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Audio session reset complete")
        } catch {
            print("❌ Audio session reset error: \(error)")
        }
    }
    
    // Set up camera status observer
    private func setupCameraObserver() {
        // Create observer to monitor camera session status
        NotificationCenter.default.addObserver(
            forName: .cameraSessionDidStart,
            object: nil,
            queue: .main
        ) { [self] notification in
            
            // Camera started successfully
            print("📱 Received camera session started notification")
            
            // Only proceed if we're in the starting process
            if self.isStartingExercise {
                // Continue with the exercise setup after camera is ready
                self.continueExerciseSetupAfterCamera()
            }
        }
        
        // Observer for camera failure
        NotificationCenter.default.addObserver(
            forName: .cameraSessionDidFail,
            object: nil,
            queue: .main
        ) { [self] notification in
            
            print("📱 Received camera session failed notification")
            
            // Handle camera failure during exercise start
            if self.isStartingExercise {
                self.handleCameraFailure()
            }
        }
    }
    
    // Remove camera observers
    private func removeCameraObserver() {
        NotificationCenter.default.removeObserver(self, name: .cameraSessionDidStart, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cameraSessionDidFail, object: nil)
    }
    
    // Set up notification observer for the exercise coach
    private func setupExerciseCoachObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ExerciseFeedback"),
            object: nil,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                          let message = userInfo["message"] as? String else {
                        return
                    }
            
            // Add message to the coach messages
            self.coachMessages.append(message)
            
            // Show the feedback
            self.showCoachFeedback = true
            
            // Auto-hide after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if self.isExerciseActive {
                    self.showCoachFeedback = false
                }
            }
        }
    }
    
    // Remove notification observer
    private func removeExerciseCoachObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("ExerciseFeedback"),
            object: nil
        )
    }
    
    // Handle camera failure during exercise setup
    private func handleCameraFailure() {
        print("❌ Camera failed to start during exercise setup")
        
        // End any potentially started ElevenLabs session
        voiceManager.endElevenLabsSession()
        
        // Reset all exercise-related state
        resourceCoordinator.stopExerciseSession()
        visionManager.stopProcessing()
        
        // Show error message to user
        DispatchQueue.main.async {
            self.cameraStartupError = true
            self.errorMessage = "Failed to start the camera. Please try again or restart the app."
            self.showingErrorAlert = true
            self.isStartingExercise = false
            self.isTransitioning = false
        }
    }
    
    private func startExercise() {
        // Prevent multiple starts or starts during transitions
        guard !isExerciseActive && !isTransitioning && !isStartingExercise else {
            print("⚠️ Exercise already active or transitioning - ignoring start request")
            return
        }
        
        // DEBUG PRINT: track why the view is disappearing
        print("🔍 EXERCISE START INITIATED BY \(Thread.callStackSymbols)")
        
        // Set flags immediately to prevent multiple calls
        isTransitioning = true
        isStartingExercise = true
        cameraStartupError = false
        
        // Add extra delay on first run
        let firstRunDelay: TimeInterval = hasStartedExerciseBefore ? 0 : 1.0
        
        print("🚀 Starting exercise: \(exercise.name)")
        if !hasStartedExerciseBefore {
            print("⏱️ Adding first-run delay of \(firstRunDelay) seconds")
        }
        
        // Print debug info
        resourceCoordinator.printAudioRouteInfo()
        
        // IMPORTANT: First end any existing sessions with a completion handler
        voiceManager.endElevenLabsSession { [self] in
            // Add delay for first run
            DispatchQueue.main.asyncAfter(deadline: .now() + firstRunDelay) { [self] in
                print("🔄 Previous session ended, starting exercise session")
                
                // Start the exercise session coordination
                resourceCoordinator.startExerciseSession { [self] success in
                    guard success else {
                        print("❌ Failed to start exercise session")
                        DispatchQueue.main.async {
                            self.errorMessage = "Failed to set up required resources."
                            self.showingErrorAlert = true
                            self.isStartingExercise = false
                            self.isTransitioning = false
                        }
                        return
                    }
                    
                    print("✅ Resource coordinator session started")
                    
                    // Critical change: Set timeout for camera startup
                    setupCameraStartupTimeout()
                    
                    // Start camera BEFORE starting the voice agent
                    // This will trigger the camera observer when successful
                    cameraManager.startSession(withNotification: true)
                    
                    print("📷 Camera start requested - waiting for confirmation...")
                }
            }
        }
    }
    
    // Continue setup after camera is ready
    private func continueExerciseSetupAfterCamera() {
        print("✅ Camera is running, continuing exercise setup...")
        
        // Start vision processing
        visionManager.startProcessing(cameraManager.videoOutput)
        print("📷 Vision processing started")
        
        // Now start the exercise coach agent
        voiceManager.startExerciseCoachAgent { [self] in
            print("🎤 Exercise coach agent started")
            
            DispatchQueue.main.async {
                // Setup timer
                remainingTime = exercise.duration
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    if remainingTime > 0 {
                        remainingTime -= 1
                    } else {
                        stopExercise()
                    }
                }
                
                // Initialize coach messages
                coachMessages = ["I'll help guide you through this exercise. Let me see your form..."]
                showCoachFeedback = true
                
                // Auto-hide initial message after a few seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if isExerciseActive {
                        showCoachFeedback = false
                    }
                }
                
                // Update UI AFTER everything is ready
                isExerciseActive = true
                isStartingExercise = false
                isTransitioning = false
                
                // Set flag indicating we've started at least once
                hasStartedExerciseBefore = true
                
                //设置成扬声器播放
                do{
                  try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                }
                catch {
                   
                }
                
                print("🏁 Exercise fully started and UI updated")
            }
        }
    }
    
    // Set up a timeout for camera startup to prevent hanging
    private func setupCameraStartupTimeout() {
        // If camera doesn't start within 5 seconds, abort
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [self] in
            // Only proceed if conditions are still valid
            if isStartingExercise && !isExerciseActive && !cameraStartupError {
                print("⏰ Camera startup timeout occurred")
                handleCameraFailure()
            }
        }
    }
    
    private func stopExercise() {
        print("🛑 Stopping exercise session")
        isStoppingExercise = true
        
        // Stop the timer
        timer?.invalidate()
        timer = nil
        
        // Calculate exercise duration
        exerciseDuration = exercise.duration - remainingTime
        
        // Set current exercise ID in VoiceManager and end session
        voiceManager.setCurrentExercise(id: exercise.firestoreId ?? exercise.id.uuidString)
        voiceManager.endExerciseSession()
        
        // Clean up resources
        resourceCoordinator.stopExerciseSession()
        visionManager.stopProcessing()
        cameraManager.resetSession()
        
        // Reset states
        DispatchQueue.main.async {
            self.isExerciseActive = false
            self.isStoppingExercise = false
            self.showingExerciseReport = true
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func saveModifications() {
        // Show loading indicator
        isUploading = true
        uploadError = nil
        
        // Prepare video data if available
        var videoData: Data? = nil
        if let recordedVideoURL = self.recordedVideoURL {
            do {
                videoData = try Data(contentsOf: recordedVideoURL)
            } catch {
                self.uploadError = "Failed to read video data: \(error.localizedDescription)"
                self.isUploading = false
                return
            }
        }
        
        // Construct the request body
        var requestBody: [String: Any] = [
            "pt_id": "pt-uuid", // Replace with actual PT ID or fetch from UserDefaults
            "patient_id": UserDefaults.standard.string(forKey: "PatientID") ?? UUID().uuidString,
            "patient_exercise_id": exercise.id.uuidString,
            "modifications": [
                "frequency": self.modifiedFrequency,
                "sets": self.modifiedSets,
                "repetitions": self.modifiedReps,
                "notes": self.modifiedNotes
            ]
        ]
        
        // Add video data if available
        if let videoData = videoData {
            requestBody["custom_video"] = [
                "base64_data": videoData.base64EncodedString(),
                "content_type": "video/mp4",
                "filename": "\(exercise.id)-custom.mp4"
            ]
        }
        
        // Convert request body to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            self.uploadError = "Failed to create request data"
            self.isUploading = false
            return
        }
        
        // Create the URL request
        let urlString = "https://us-central1-pep-pro.cloudfunctions.net/modify_exercise"
        guard let url = URL(string: urlString) else {
            self.uploadError = "Invalid API URL"
            self.isUploading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Create the data task
        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            DispatchQueue.main.async {
                self.isUploading = false
                
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    self.uploadError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.uploadError = "Invalid response from server"
                    return
                }
                
                guard let data = data else {
                    self.uploadError = "No data received from server"
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    self.uploadError = "Server error: HTTP \(httpResponse.statusCode)"
                    if let errorMessage = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorText = errorMessage["error"] as? String {
                        self.uploadError = errorText
                    }
                    return
                }
                
                // Parse the response
                do {
                    let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let status = responseDict?["status"] as? String, status == "success" {
                        // Handle success
                        self.uploadError = nil
                    } else {
                        self.uploadError = responseDict?["error"] as? String ?? "Unknown error"
                    }
                } catch {
                    self.uploadError = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }
        
        // Start the request
        task.resume()
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

// MARK: - Notification names for camera status
extension Notification.Name {
    static let cameraSessionDidStart = Notification.Name("CameraSessionDidStart")
    static let cameraSessionDidFail = Notification.Name("CameraSessionDidFail")
}
