import SwiftUI
import ARKit
import Vision

@Observable
@MainActor
class HandTrackerState {
    var detectedHands: [HandJoints] = []
    var isHandDetected = false
}

struct HandJoints {
    let fingerLines: [[CGPoint]]
    let joints: [CGPoint]
}

struct ARHandView: View {
    let sessionModel: ARSessionModel
    let resetTrigger: Int
    @State private var trackerState = HandTrackerState()
    
    var body: some View {
        ZStack {
            ARHandCameraView(sessionModel: sessionModel, trackerState: trackerState, resetTrigger: resetTrigger)
                .ignoresSafeArea()
            
            // Visual overlay of glowing hand tracking joints
            Canvas { context, size in
                for hand in trackerState.detectedHands {
                    // Draw connecting skeletal lines
                    for line in hand.fingerLines {
                        if line.count > 1 {
                            var path = Path()
                            path.move(to: line[0])
                            for point in line.dropFirst() {
                                path.addLine(to: point)
                            }
                            // Glow line style
                            context.stroke(path, with: .color(.cyan.opacity(0.8)), lineWidth: 3)
                            
                            context.drawLayer { glowContext in
                                glowContext.addFilter(.blur(radius: 3))
                                glowContext.stroke(path, with: .color(.cyan.opacity(0.5)), lineWidth: 6)
                            }
                        }
                    }
                    
                    // Draw joint nodes
                    for point in hand.joints {
                        var dotPath = Path()
                        dotPath.addEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                        context.fill(dotPath, with: .color(.white))
                        
                        context.drawLayer { glowContext in
                            glowContext.addFilter(.blur(radius: 4))
                            var glowPath = Path()
                            glowPath.addEllipse(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
                            glowContext.fill(glowPath, with: .color(.cyan))
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

struct ARHandCameraView: UIViewRepresentable {
    let sessionModel: ARSessionModel
    let trackerState: HandTrackerState
    let resetTrigger: Int
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.session.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        
        context.coordinator.startSession(in: arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if context.coordinator.lastResetTrigger != resetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            context.coordinator.resetSession(in: uiView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(sessionModel: sessionModel, trackerState: trackerState)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let sessionModel: ARSessionModel
        let trackerState: HandTrackerState
        var lastResetTrigger = 0
        
        private var isProcessingFrame = false
        private let handPoseRequest = VNDetectHumanHandPoseRequest()
        private let processingQueue = DispatchQueue(label: "com.arkitexplore.handprocessing", qos: .userInteractive)
        
        init(sessionModel: ARSessionModel, trackerState: HandTrackerState) {
            self.sessionModel = sessionModel
            self.trackerState = trackerState
            super.init()
            handPoseRequest.maximumHandCount = 2
        }
        
        func startSession(in arView: ARSCNView) {
            let configuration = ARWorldTrackingConfiguration()
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            Task { @MainActor in
                sessionModel.isSessionRunning = true
            }
        }
        
        func resetSession(in arView: ARSCNView) {
            startSession(in: arView)
            
            Task { @MainActor in
                trackerState.detectedHands = []
                trackerState.isHandDetected = false
                sessionModel.isHandDetected = false
            }
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Check tracking state
            let trackingState = frame.camera.trackingState
            Task { @MainActor in
                sessionModel.updateTrackingState(trackingState)
            }
            
            // Limit processing to avoid blocking frames
            guard !isProcessingFrame else { return }
            isProcessingFrame = true
            
            let pixelBuffer = frame.capturedImage
            
            // Get screen/viewport size from active window
            let viewportSize = UIScreen.main.bounds.size
            
            // Perform Vision request on background queue
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                // ARKit frames are typically landscape left/right on backend, but let's align orientation
                let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                
                do {
                    try requestHandler.perform([self.handPoseRequest])
                    if let results = self.handPoseRequest.results, !results.isEmpty {
                        var parsedHands: [HandJoints] = []
                        
                        for handObservation in results {
                            let joints = try self.extractJointPoints(from: handObservation, frame: frame, viewportSize: viewportSize)
                            if !joints.isEmpty {
                                let lines = self.createFingerLines(joints: joints)
                                parsedHands.append(HandJoints(fingerLines: lines, joints: Array(joints.values)))
                            }
                        }
                        
                        DispatchQueue.main.async {
                            self.trackerState.detectedHands = parsedHands
                            self.trackerState.isHandDetected = true
                            self.sessionModel.isHandDetected = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.trackerState.detectedHands = []
                            self.trackerState.isHandDetected = false
                            self.sessionModel.isHandDetected = false
                        }
                    }
                } catch {
                    print("Hand Pose estimation failed: \(error)")
                }
                
                self.isProcessingFrame = false
            }
        }
        
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let trackingState = camera.trackingState
            Task { @MainActor in
                sessionModel.updateTrackingState(trackingState)
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in
                sessionModel.errorMessage = error.localizedDescription
            }
        }
        
        // MARK: - Hand Landmark Parser
        
        private func extractJointPoints(
            from observation: VNHumanHandPoseObservation,
            frame: ARFrame,
            viewportSize: CGSize
        ) throws -> [VNHumanHandPoseObservation.JointName: CGPoint] {
            var jointsMap: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
            
            // Retrieve all landmarks
            let recognizedPoints = try observation.recognizedPoints(.all)
            
            // Map each point to viewport space
            for (key, point) in recognizedPoints where point.confidence > 0.4 {
                // Point is normalized with 0,0 at bottom-left of image
                // Map using ARKit frame displayTransform to perfectly match the projected video background
                let imagePoint = CGPoint(x: point.x, y: point.y)
                
                // displayTransform translates normalized image coordinates to normalized viewport coordinates
                // We use .portrait as the screen display is locked to portrait
                let displayTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
                let normalizedViewportPoint = imagePoint.applying(displayTransform)
                
                // Convert normalized viewport point to screen points (mirrored for 1-to-1 movement)
                let screenPoint = CGPoint(
                    x: (1.0 - normalizedViewportPoint.x) * viewportSize.width,
                    y: normalizedViewportPoint.y * viewportSize.height
                )
                
                jointsMap[key] = screenPoint
            }
            
            return jointsMap
        }
        
        private func createFingerLines(joints: [VNHumanHandPoseObservation.JointName: CGPoint]) -> [[CGPoint]] {
            var lines: [[CGPoint]] = []
            
            // Map helper to fetch points
            func pts(_ names: [VNHumanHandPoseObservation.JointName]) -> [CGPoint] {
                names.compactMap { joints[$0] }
            }
            
            // Thumb
            lines.append(pts([.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]))
            
            // Index
            lines.append(pts([.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]))
            
            // Middle
            lines.append(pts([.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]))
            
            // Ring
            lines.append(pts([.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]))
            
            // Little
            lines.append(pts([.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]))
            
            // Knuckle connection arc
            lines.append(pts([.indexMCP, .middleMCP, .ringMCP, .littleMCP]))
            
            return lines
        }
    }
}
