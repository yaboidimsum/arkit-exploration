import SwiftUI
import ARKit
import Vision
import SceneKit

struct ARObjectTaggingView: UIViewRepresentable {
    let sessionModel: ARSessionModel
    let resetTrigger: Int
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.session.delegate = context.coordinator
        arView.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        
        context.coordinator.arView = arView
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
        Coordinator(sessionModel: sessionModel)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let sessionModel: ARSessionModel
        var lastResetTrigger = 0
        weak var arView: ARSCNView?
        
        private var isProcessingFrame = false
        private var activeTagNode: SCNNode?
        private let processingQueue = DispatchQueue(label: "com.arkitexplore.mlprocessing", qos: .userInteractive)
        
        // Vision requests
        private let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        private let classificationRequest = VNClassifyImageRequest()
        
        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
            super.init()
        }
        
        func startSession(in arView: ARSCNView) {
            let configuration = ARWorldTrackingConfiguration()
            // Enable plane detection so we have surfaces to raycast against
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.isLightEstimationEnabled = true
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            Task { @MainActor in
                sessionModel.isSessionRunning = true
            }
        }
        
        func resetSession(in arView: ARSCNView) {
            removeActiveTag()
            startSession(in: arView)
            
            Task { @MainActor in
                sessionModel.isObjectDetected = false
                sessionModel.detectedObjectName = ""
            }
        }
        
        private func removeActiveTag() {
            activeTagNode?.removeFromParentNode()
            activeTagNode = nil
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Update tracking state
            let trackingState = frame.camera.trackingState
            Task { @MainActor in
                sessionModel.updateTrackingState(trackingState)
            }
            
            // Limit processing frequency (approx 4 times per second)
            guard !isProcessingFrame else { return }
            isProcessingFrame = true
            
            let pixelBuffer = frame.capturedImage
            let viewportSize = UIScreen.main.bounds.size
            
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                
                let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                
                do {
                    // 1. Run Saliency detection to locate objects
                    try requestHandler.perform([self.saliencyRequest])
                    
                    if let saliencyResults = self.saliencyRequest.results as? [VNSaliencyImageObservation],
                       let primaryObject = saliencyResults.first?.salientObjects?.first {
                        
                        let boundingBox = primaryObject.boundingBox
                        
                        // 2. Set Region of Interest for Classification
                        self.classificationRequest.regionOfInterest = boundingBox
                        try requestHandler.perform([self.classificationRequest])
                        
                        if let classificationResults = self.classificationRequest.results as? [VNClassificationObservation],
                           let bestMatch = classificationResults.first(where: { $0.confidence > 0.30 }) {
                            
                            // Clean up label synonym lists
                            let cleanLabel = bestMatch.identifier.components(separatedBy: ",").first ?? bestMatch.identifier
                            let capitalizedLabel = cleanLabel.capitalized
                            
                            // Find normalized center coordinate of target bounding box
                            // Note: Vision coordinates are bottom-left (y is up), convert to ARKit displayTransform orientation
                            let centerPoint = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
                            
                            DispatchQueue.main.async {
                                self.processDetection(
                                    label: capitalizedLabel,
                                    confidence: bestMatch.confidence,
                                    normalizedPoint: centerPoint,
                                    frame: frame,
                                    viewportSize: viewportSize,
                                    session: session
                                )
                            }
                        }
                    }
                } catch {
                    print("CoreML / Vision pipeline failed: \(error)")
                }
                
                // Throttled delay
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                    self.isProcessingFrame = false
                }
            }
        }
        
        private func processDetection(
            label: String,
            confidence: Float,
            normalizedPoint: CGPoint,
            frame: ARFrame,
            viewportSize: CGSize,
            session: ARSession
         ) {
            // Eagerly update HUD telemetry so the user sees classification text immediately
            sessionModel.isObjectDetected = true
            sessionModel.detectedObjectName = "\(label) (\(Int(confidence * 100))%)"
            
            guard let arView = self.arView else { return }
            
            // Map Vision normalized coordinates (bottom-left) to ARKit normalized screen coordinates (top-left)
            let displayTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
            let viewportPoint = normalizedPoint.applying(displayTransform)
            
            // Define hitTest types to query planes and raw feature points on physical objects
            let hitTestTypes: ARHitTestResult.ResultType = [
                .existingPlaneUsingGeometry,
                .estimatedHorizontalPlane,
                .estimatedVerticalPlane,
                .featurePoint
            ]
            
            // Convert normalized viewport coordinates (0...1) to view pixel coordinates for hitTest
            let screenPoint = CGPoint(
                x: viewportPoint.x * arView.bounds.width,
                y: viewportPoint.y * arView.bounds.height
            )
            
            let hitResults = arView.hitTest(screenPoint, types: hitTestTypes)
            let hitPosition: SCNVector3
            
            if let firstHit = hitResults.first {
                let transform = firstHit.worldTransform
                // If it hit a feature point (i.e. on the object), place it directly on the object's surface
                hitPosition = SCNVector3(
                    transform.columns.3.x,
                    transform.columns.3.y + 0.04, // Float slightly above the object
                    transform.columns.3.z
                )
            } else {
                // Fallback: Place it 0.5 meters directly in front of the camera frame
                let cameraTransform = frame.camera.transform
                let forwardVector = cameraTransform.columns.2 // right-handed coordinates Z is backwards
                let cameraPosition = cameraTransform.columns.3
                
                hitPosition = SCNVector3(
                    cameraPosition.x - forwardVector.x * 0.5,
                    cameraPosition.y - forwardVector.y * 0.5,
                    cameraPosition.z - forwardVector.z * 0.5
                )
            }
            
            let tagText = "\(label) (\(Int(confidence * 100))%)"
            update3DTag(text: tagText, position: hitPosition, in: arView.scene.rootNode)
        }
        
        private func update3DTag(text: String, position: SCNVector3, in rootNode: SCNNode) {
            // Remove old tag first
            removeActiveTag()
            
            // Create holographic text node
            let tagNode = createTagNode(text: text, themeColor: .systemGreen)
            tagNode.position = position
            rootNode.addChildNode(tagNode)
            self.activeTagNode = tagNode
        }
        
        private func createTagNode(text: String, themeColor: UIColor) -> SCNNode {
            let parent = SCNNode()
            
            // 1. Generate a bold rectangular border texture dynamically
            let borderSize = CGSize(width: 256, height: 256)
            let borderWidth: CGFloat = 16.0 // Bold border
            let textureImage = generateBorderImage(size: borderSize, borderWidth: borderWidth, color: themeColor)
            
            // 2. 2D Bounding Square framing the object
            let framePlane = SCNPlane(width: 0.35, height: 0.35)
            let planeMaterial = SCNMaterial()
            planeMaterial.diffuse.contents = textureImage
            planeMaterial.emission.contents = textureImage // Glowing neon lines
            planeMaterial.isDoubleSided = true
            framePlane.materials = [planeMaterial]
            
            let borderNode = SCNNode(geometry: framePlane)
            parent.addChildNode(borderNode)
            
            // 3. Large 3D Text centered inside/on top of the bounding square
            let scnText = SCNText(string: text, extrusionDepth: 0.02)
            scnText.font = UIFont.systemFont(ofSize: 0.25, weight: .bold)
            scnText.firstMaterial?.diffuse.contents = UIColor.white
            scnText.firstMaterial?.emission.contents = UIColor.white
            
            let textNode = SCNNode(geometry: scnText)
            textNode.scale = SCNVector3(0.12, 0.12, 0.12)
            
            // Center the text node horizontally, and float it just above the top edge of the square
            let (minVec, maxVec) = scnText.boundingBox
            let textWidth = maxVec.x - minVec.x
            textNode.position = SCNVector3(-textWidth * 0.06, 0.20, 0.01)
            parent.addChildNode(textNode)
            
            // Billboard constraint so the entire tag faces the camera
            let billboardConstraint = SCNBillboardConstraint()
            billboardConstraint.freeAxes = .all
            parent.constraints = [billboardConstraint]
            
            return parent
        }
        
        private func generateBorderImage(size: CGSize, borderWidth: CGFloat, color: UIColor) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let rect = CGRect(origin: .zero, size: size)
                context.cgContext.clear(rect) // Transparent interior
                
                // Draw bold border
                context.cgContext.setStrokeColor(color.cgColor)
                context.cgContext.setLineWidth(borderWidth)
                context.cgContext.stroke(rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
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
    }
}
