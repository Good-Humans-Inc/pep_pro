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
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    
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
        
        // Configure the vision request
        bodyPoseRequest.maximumNumberOfBodyPoses = 1 // Only track one person
        setupVision()
    }
    
    private func setupVision() {
        // Set up pose detection request
        if let poseRequest = try? VNDetectHumanBodyPoseRequest(completionHandler: handlePoses) {
            requests = [poseRequest]
        }
    }
    
    private func handlePoses(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.processingError = error.localizedDescription
                return
            }
            
            guard let observations = request.results as? [VNHumanBodyPoseObservation] else {
                return
            }
            
            self.detectedPoses = observations
        }
    }
    
    // Update preview layer info for coordinate conversion
    func updatePreviewLayer(rect: CGRect) {
        previewLayer = rect
        updateTransformMatrix()
    }
    
    private func updateTransformMatrix() {
        // Create transform matrix to convert normalized coordinates to view coordinates
        transformMatrix = CGAffineTransform(scaleX: previewLayer.width, y: previewLayer.height)
    }
    
    // Process frame for pose detection
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !isProcessing else { return }
        
        isProcessing = true
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([bodyPoseRequest])
            
            guard let observation = bodyPoseRequest.results?.first else {
                isProcessing = false
                return
            }
            
            // Process detected pose
            processObservation(observation)
            
        } catch {
            DispatchQueue.main.async {
                self.processingError = error.localizedDescription
            }
        }
        
        isProcessing = false
    }
    
    private func processObservation(_ observation: VNHumanBodyPoseObservation) {
        var newPose = BodyPose()
        
        // Process each joint type
        for jointType in BodyJointType.allCases {
            guard let visionJoint = jointType.visionJointName else { continue }
            
            do {
                let point = try observation.recognizedPoint(visionJoint)
                
                // Convert normalized coordinates to view coordinates
                let transformedPoint = point.location.applying(transformMatrix)
                
                // Create body joint with transformed coordinates
                let joint = BodyJoint(
                    id: jointType,
                    position: transformedPoint,
                    confidence: point.confidence
                )
                
                // Add joint to pose if confidence is high enough
                if joint.isValid {
                    newPose.joints[jointType] = joint
                }
                
            } catch {
                print("Failed to get point for joint \(jointType): \(error)")
            }
        }
        
        // Update pose on main thread
        DispatchQueue.main.async {
            self.currentBodyPose = newPose
            print("Updated pose with \(newPose.joints.count) valid joints")
            
            // Print joint positions for debugging
            print("-----------------------------------")
            for (type, joint) in newPose.joints {
                print("\(type): position=\(joint.position), confidence=\(joint.confidence)")
            }
            print("-----------------------------------")
        }
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
    }
    
    func stopProcessing() {
        isProcessing = false
        DispatchQueue.main.async {
            self.currentBodyPose = BodyPose()
        }
    }
    
    func cleanUp() {
        stopProcessing()
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
