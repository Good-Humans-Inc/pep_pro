import Foundation
import Vision
import AVFoundation
import UIKit
import Combine

class VisionManager: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var currentBodyPose = BodyPose()
    @Published var isProcessing = false
    @Published var processingError: String?
    
    // Transform matrix for coordinate conversion
    private var transformMatrix: CGAffineTransform = .identity
    
    // Vision request
    private var bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    
    // Processing queue
    private let visionQueue = DispatchQueue(label: "com.kneerecovery.visionProcessing",
                                          qos: .userInteractive)
    
    // Timer for controlling frame processing rate
    private var processingTimer: Timer?
    private let frameProcessingInterval: TimeInterval = 0.1 // Process frames every 100ms
    
    // Size info for coordinate conversion
    private var previewLayer: CGRect = .zero
    
    override init() {
        super.init()
        
        // Configure the vision request
        // bodyPoseRequest.maximumNumberOfBodyPoses = 1 // Only track one person
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
    }
    
    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isProcessing,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([bodyPoseRequest])
            
            guard let observation = bodyPoseRequest.results?.first else {
                return
            }
            
            // Convert normalized coordinates to the view's coordinates
            let width = previewLayer.width
            let height = previewLayer.height
            
            // Create transform matrix to convert from normalized coordinates to view coordinates
            let transformMatrix = CGAffineTransform(scaleX: width, y: height)
            
            // Create body pose from observation
            var detectedPose = BodyPose()
            
            // Process each joint from the observation
            for jointType in BodyJointType.allCases {
                guard let visionJointName = jointType.visionJointName else { continue }
                
                do {
                    let jointPoint = try observation.recognizedPoint(visionJointName)
                    let normalizedPosition = CGPoint(x: jointPoint.x, y: 1 - jointPoint.y) // Flip Y coordinate
                    let transformedPosition = normalizedPosition.applying(transformMatrix)
                    
                    detectedPose.joints[jointType] = BodyJoint(
                        id: jointType,
                        position: transformedPosition,
                        confidence: jointPoint.confidence
                    )
                } catch {
                    print("Error getting joint \(jointType): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.currentBodyPose = detectedPose
                self.logJointCoordinates(detectedPose)
            }
        } catch {
            DispatchQueue.main.async {
                self.processingError = error.localizedDescription
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
