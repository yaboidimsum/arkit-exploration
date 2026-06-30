import SwiftUI
import ARKit

/// An observable model that manages the status and telemetry of various ARKit sessions.
@Observable
@MainActor
public final class ARSessionModel {
    public var isSessionRunning = false
    public var trackingStateText = "Not Started"
    public var detectedPlanesCount = 0
    public var isFaceDetected = false
    public var isBodyDetected = false
    public var isHandDetected = false
    public var isObjectDetected = false
    public var detectedObjectName = ""
    public var errorMessage: String? = nil
    
    public init() {}
    
    public func reset() {
        isSessionRunning = false
        trackingStateText = "Not Started"
        detectedPlanesCount = 0
        isFaceDetected = false
        isBodyDetected = false
        isHandDetected = false
        isObjectDetected = false
        detectedObjectName = ""
        errorMessage = nil
    }
    
    public func updateTrackingState(_ trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .notAvailable:
            trackingStateText = "Not Available"
        case .normal:
            trackingStateText = "Normal Tracking"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                trackingStateText = "Limited: Excessive Motion"
            case .insufficientFeatures:
                trackingStateText = "Limited: Low Light / Few Features"
            case .initializing:
                trackingStateText = "Limited: Initializing..."
            case .relocalizing:
                trackingStateText = "Limited: Relocalizing..."
            @unknown default:
                trackingStateText = "Limited: Unknown Reason"
            }
        }
    }
}
