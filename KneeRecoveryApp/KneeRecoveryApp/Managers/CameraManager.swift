import Foundation
import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var isSessionRunning = false
    @Published var isCameraAuthorized = false
    @Published var cameraError: String?
    
    // Camera capture session
    let session = AVCaptureSession()
    var videoOutput = AVCaptureVideoDataOutput()
    
    // Video processing queue
    private let videoProcessingQueue = DispatchQueue(label: "com.kneerecovery.videoProcessing",
                                                   qos: .userInteractive)
    
    private var setupResult: SessionSetupResult = .notDetermined
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
        case notDetermined
    }
    
    override init() {
        super.init()
        
        // Check camera authorization status
        checkAuthorization()
    }
    
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setupResult = .success
            self.isCameraAuthorized = true
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupResult = .success
                        self.isCameraAuthorized = true
                    } else {
                        self.setupResult = .notAuthorized
                        self.isCameraAuthorized = false
                    }
                }
            }
        default:
            setupResult = .notAuthorized
            isCameraAuthorized = false
        }
    }
    
    func setupSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = .high
        
        // Add video input
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose front camera
            if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCameraDevice
            } else {
                // No front camera, use default
                defaultVideoDevice = AVCaptureDevice.default(for: .video)
            }
            
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add video output
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        } else {
            print("Could not add video output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    func startSession() {
        if setupResult != .success {
            checkAuthorization()
        }
        
        if setupResult == .success && !session.isRunning {
            setupSession()
            videoProcessingQueue.async {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    func stopSession() {
        if session.isRunning {
            videoProcessingQueue.async {
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    // Clean up method
    func cleanUp() {
        stopSession()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Video frames will be processed by the VisionManager via its delegate method
        // This method is left empty intentionally
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
    }
}
