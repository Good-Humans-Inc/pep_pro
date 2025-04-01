import SwiftUI
import AVFoundation
import AVKit

// MARK: - Custom Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession?
    @Binding var previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black // 设置默认背景色
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 确保在主线程执行
        DispatchQueue.main.async {
            // 如果已有预览层，更新它的session和frame
            if let existingLayer = previewLayer {
                existingLayer.session = session
                existingLayer.frame = uiView.bounds
            }
            // 如果没有预览层且session存在，创建新的
            else if let session = session {
                let newLayer = AVCaptureVideoPreviewLayer(session: session)
                newLayer.videoGravity = .resizeAspectFill
                newLayer.frame = uiView.bounds
                uiView.layer.addSublayer(newLayer)
                previewLayer = newLayer
            }
            
            // 如果session为nil，移除现有预览层
            if session == nil, let layer = previewLayer {
                layer.removeFromSuperlayer()
                previewLayer = nil
            }
        }
        
                print("updateUIView")
                print(previewLayer)
    }
}

// MARK: - Custom Video Player
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Video Review View
struct VideoReviewView: View {
    let videoURL: URL
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack {
            Text("Review Exercise Video")
                .font(.headline)
                .padding()
            
            CustomVideoPlayer(url: videoURL)
                .aspectRatio(9/16, contentMode: .fit)
                .cornerRadius(12)
                .padding()
            
            HStack(spacing: 40) {
                Button(action: onReject) {
                    VStack {
                        Image(systemName: "trash")
                            .font(.system(size: 30))
                            .foregroundColor(.red)
                        Text("Discard")
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: onAccept) {
                    VStack {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 30))
                            .foregroundColor(.green)
                        Text("Use Video")
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - ExerciseVideoRecorder (Renamed to avoid conflicts)
struct ExerciseVideoRecorder: View {
    let onVideoSaved: (URL) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.presentationMode) var mode
    
    // State properties
    @State private var isRecording = false
    @State private var recordingSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var tempVideoURL: URL?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showingReviewSheet = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                CameraPreviewView(session: recordingSession, previewLayer: $previewLayer)
                    .edgesIgnoringSafeArea(.all)
                // Overlay controls
                VStack {
                    // Top bar with title
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()
                        
                        Spacer()
                        
                        Text(isRecording ? timeString(from: recordingTime) : "Record Exercise Video")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        // Spacer to balance the layout
                        Color.clear.frame(width: 40, height: 40)
                            .padding()
                    }
                    
                    Spacer()
                    
                    // Recording button
                    Button(action: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 80, height: 80)
                            
                            if isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red)
                                    .frame(width: 30, height: 30)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 70, height: 70)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            setupCaptureSession()
        }
        .onDisappear {
            stopSession()
        }
        .onChange(of: recordingSession, { oldValue, newValue in
            if newValue != nil {
                // 确保预览层更新
                previewLayer?.session = newValue
            }
        })
  
        .sheet(isPresented: $showingReviewSheet) {
            if let url = tempVideoURL {
                VideoReviewView(videoURL: url, onAccept: {
                    onVideoSaved(url)
                    presentationMode.wrappedValue.dismiss()
                }, onReject: {
                    // Delete the video and dismiss
                    try? FileManager.default.removeItem(at: url)
                    showingReviewSheet = false
                })
            }
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        self.recordingSession = session
        
        print("setupCaptureSession")
        print(session)
        
        session.beginConfiguration()
        
        // Set quality
        session.sessionPreset = .high
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Failed to get camera input")
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
            print("Failed to get audio input")
            return
        }
        
        if session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        // Add video output
        let output = AVCaptureMovieFileOutput()
        videoOutput = output
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            
            if let connection = output.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
        
        session.commitConfiguration()
        
        // Start running the session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func startRecording() {
        guard let output = videoOutput, !isRecording else { return }
        
        // Create temporary URL for video
        let tempDir = FileManager.default.temporaryDirectory
        let tempFilename = UUID().uuidString + ".mov"
        let tempURL = tempDir.appendingPathComponent(tempFilename)
        tempVideoURL = tempURL
        
        // Create a recording delegate
        let delegate = VideoRecordingDelegate { url, error in
            if let error = error {
                print("Error recording: \(error.localizedDescription)")
                return
            }
            
            print("Finished recording to \(url)")
            
            // Show review sheet after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingReviewSheet = true
            }
        }
        
        // Hold reference to delegate (important!)
        objc_setAssociatedObject(output, &AssociatedKeys.recordingDelegate, delegate, .OBJC_ASSOCIATION_RETAIN)
        
        // Start recording using the delegate
        output.startRecording(to: tempURL, recordingDelegate: delegate)
        isRecording = true
        
        // Start timer
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }
    
    private func stopRecording() {
        guard let output = videoOutput, isRecording else { return }
        
        // Stop recording
        output.stopRecording()
        isRecording = false
        
        // Stop timer
        timer?.invalidate()
        timer = nil
    }
    
    private func stopSession() {
        if isRecording {
            stopRecording()
        }
        
        recordingSession?.stopRunning()
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let tenths = Int((timeInterval * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }
}

// MARK: - Helper classes

// Keys for associated objects
private struct AssociatedKeys {
    static var recordingDelegate = "recordingDelegate"
}

// Separate class to handle recording delegation
class VideoRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let didFinishRecording: (URL, Error?) -> Void
    
    init(didFinishRecording: @escaping (URL, Error?) -> Void) {
        self.didFinishRecording = didFinishRecording
        super.init()
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Started recording to \(fileURL)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        didFinishRecording(outputFileURL, error)
    }
}

