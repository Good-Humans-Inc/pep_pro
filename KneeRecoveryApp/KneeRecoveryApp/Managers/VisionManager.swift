import Foundation
import Vision
import AVFoundation
import UIKit
import Combine

class VisionManager: NSObject, ObservableObject {
    // Reference to AppState
    private let appState: AppState
    
    // Vision request handlers
    private var requests = [VNRequest]()
    
    // Published properties for UI updates
    @Published var currentBodyPose = BodyPose()
    @Published var isProcessing = false
    @Published var processingError: String?
    @Published var detectedPoses: [VNHumanBodyPoseObservation] = []
    
    // Transform matrix for coordinate conversion
    private var transformMatrix: CGAffineTransform = .identity
    
    // Vision request
    private var bodyPoseRequest: VNDetectHumanBodyPoseRequest!
    
    // Processing queue
    private let visionQueue = DispatchQueue(label: "com.kneerecovery.visionProcessing",
                                          qos: .userInteractive)
    
    // Timer for controlling frame processing rate
    private var processingTimer: Timer?
    private let frameProcessingInterval: TimeInterval = 0.1 // Process frames every 100ms
    
    // Size info for coordinate conversion
    private var previewLayer: CGRect = .zero
    
    // Initialize with AppState
    init(appState: AppState) {
        self.appState = appState
        super.init()
        
        // Configure vision
        setupVision()
        print("👁 VisionManager initialized")
    }
    
    private func setupVision() {
        // Create and configure the pose detection request
        bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        //bodyPoseRequest.maximumNumberOfObservations = 1 // Only track one person
        requests = [bodyPoseRequest] // Add to requests array
        
        print("👁 Vision requests configured")
    }
    
    func startProcessing(_ videoOutput: AVCaptureVideoDataOutput) {
        isProcessing = true
        
        // Subscribe to video output
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        
        // Set up the preview layer size
        DispatchQueue.main.async {
            self.previewLayer = UIScreen.main.bounds
            // Update transform matrix
            self.transformMatrix = CGAffineTransform(scaleX: self.previewLayer.width, y: self.previewLayer.height)
        }
        
        //设置成扬声器播放
        do{
          try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        }
        catch {
           
        }
        
    }
    
    func stopProcessing() {
        isProcessing = false
    }
    
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isProcessing,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform(requests)
            
            guard let observation = bodyPoseRequest.results?.first else {
                print("👁 No pose detected")
                return
            }
            
            print("👁 Pose detected with confidence: \(observation.confidence)")
            
            // Convert normalized coordinates to the view's coordinates
            let width = previewLayer.width
            let height = previewLayer.height
            
            // Create body pose from observation
            var detectedPose = BodyPose()
            
            // Process each joint from the observation
            for jointType in BodyJointType.allCases {
                guard let visionJointName = jointType.visionJointName else { continue }
                
                do {
                    let jointPoint = try observation.recognizedPoint(visionJointName)
                    
                    // Only process joints with sufficient confidence
                    if jointPoint.confidence > 0.3 {
                        let normalizedPosition = CGPoint(x: jointPoint.x, y: 1 - jointPoint.y) // Flip Y coordinate
                        let transformedPosition = normalizedPosition.applying(transformMatrix)
                        
                        detectedPose.joints[jointType] = BodyJoint(
                            id: jointType,
                            position: transformedPosition,
                            confidence: jointPoint.confidence
                        )
                    }
                } catch {
                    print("👁 Error getting joint \(jointType): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.currentBodyPose = detectedPose
                self.logJointCoordinates(detectedPose)
                
                // Update AppState
                self.appState.visionState.currentPose = detectedPose
                self.appState.visionState.isProcessing = true
                self.appState.visionState.error = nil
            }
        } catch {
            print("👁 Vision processing error: \(error)")
            DispatchQueue.main.async {
                self.processingError = error.localizedDescription
                self.appState.visionState.error = error.localizedDescription
            }
        }
    }
    
    // Log joint coordinates to the console
    private func logJointCoordinates(_ pose: BodyPose) {
        print("BODY POSE JOINTS:")
        
        for (jointType, joint) in pose.joints {
            if joint.isValid {
                print("\(jointType.rawValue): x=\(joint.position.x), y=\(joint.position.y), confidence=\(joint.confidence)")
            }
        }
        
        print("-----------------------------------")
    }
    
    func cleanUp() {
        isProcessing = false
        detectedPoses.removeAll()
        processingError = nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension VisionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process frames at controlled rate to avoid overwhelming CPU
        processFrame(sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
    }
}
