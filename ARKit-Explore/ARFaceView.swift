import SwiftUI
import ARKit
import SceneKit

struct ARFaceView: UIViewRepresentable {
    let sessionModel: ARSessionModel
    let selectedStyle: FaceStyle
    let resetTrigger: Int
    
    enum FaceStyle: String, CaseIterable, Identifiable {
        case wireframe = "Sci-Fi Grid"
        case mask = "Neon Hologram"
        case cyberHUD = "Cyber HUD"
        
        var id: String { self.rawValue }
    }
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        
        // Start the face tracking session
        context.coordinator.startSession(in: arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if context.coordinator.lastResetTrigger != resetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            context.coordinator.resetSession(in: uiView)
        }
        
        if context.coordinator.currentStyle != selectedStyle {
            context.coordinator.currentStyle = selectedStyle
            context.coordinator.updateFaceStyle()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(sessionModel: sessionModel, selectedStyle: selectedStyle)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let sessionModel: ARSessionModel
        var currentStyle: FaceStyle
        var lastResetTrigger = 0
        
        private var faceGeometry: ARSCNFaceGeometry?
        private var faceNode: SCNNode?
        private var hudOverlayNode: SCNNode?
        
        init(sessionModel: ARSessionModel, selectedStyle: FaceStyle) {
            self.sessionModel = sessionModel
            self.currentStyle = selectedStyle
        }
        
        func startSession(in arView: ARSCNView) {
            guard ARFaceTrackingConfiguration.isSupported else {
                Task { @MainActor in
                    sessionModel.errorMessage = "Face tracking is not supported on this device. Requires TrueDepth camera."
                }
                return
            }
            
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            // Create face geometry utilizing device Metal contexts
            if let device = arView.device {
                faceGeometry = ARSCNFaceGeometry(device: device)
            }
            
            Task { @MainActor in
                sessionModel.isSessionRunning = true
            }
        }
        
        func resetSession(in arView: ARSCNView) {
            faceNode?.removeFromParentNode()
            faceNode = nil
            hudOverlayNode = nil
            startSession(in: arView)
            
            Task { @MainActor in
                sessionModel.isFaceDetected = false
            }
        }
        
        // MARK: - Face Styling
        
        func updateFaceStyle() {
            guard let geometry = faceGeometry else { return }
            
            // Customize face mesh material
            let material = SCNMaterial()
            
            switch currentStyle {
            case .wireframe:
                material.diffuse.contents = UIColor.clear
                material.fillMode = .lines // Wireframe mode
                material.emission.contents = UIColor.systemCyan
            case .mask:
                material.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.2)
                material.fillMode = .fill
                material.specular.contents = UIColor.white
                material.shininess = 0.8
                material.emission.contents = UIColor.systemPurple.withAlphaComponent(0.3)
            case .cyberHUD:
                material.diffuse.contents = UIColor.clear
                material.fillMode = .fill
                material.emission.contents = UIColor.clear
            }
            
            geometry.materials = [material]
            
            // Manage additional overlays
            if currentStyle == .cyberHUD {
                createCyberHUD()
            } else {
                hudOverlayNode?.removeFromParentNode()
                hudOverlayNode = nil
            }
        }
        
        private func createCyberHUD() {
            hudOverlayNode?.removeFromParentNode()
            
            let parentHUD = SCNNode()
            
            // Left eye ring target
            let leftTorus = SCNTorus(ringRadius: 0.015, pipeRadius: 0.002)
            leftTorus.firstMaterial?.diffuse.contents = UIColor.systemRed
            leftTorus.firstMaterial?.emission.contents = UIColor.systemRed
            let leftEyeNode = SCNNode(geometry: leftTorus)
            leftEyeNode.position = SCNVector3(-0.03, 0.03, 0.04) // Relative positions corresponding to eye location
            leftEyeNode.eulerAngles.x = .pi / 2
            
            // Right eye ring target
            let rightTorus = SCNTorus(ringRadius: 0.015, pipeRadius: 0.002)
            rightTorus.firstMaterial?.diffuse.contents = UIColor.systemRed
            rightTorus.firstMaterial?.emission.contents = UIColor.systemRed
            let rightEyeNode = SCNNode(geometry: rightTorus)
            rightEyeNode.position = SCNVector3(0.03, 0.03, 0.04)
            rightEyeNode.eulerAngles.x = .pi / 2
            
            // Forehead data HUD board
            let hudPlane = SCNPlane(width: 0.08, height: 0.02)
            hudPlane.firstMaterial?.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.6)
            hudPlane.firstMaterial?.emission.contents = UIColor.systemGreen.withAlphaComponent(0.8)
            let hudNode = SCNNode(geometry: hudPlane)
            hudNode.position = SCNVector3(0, 0.08, 0.05)
            
            parentHUD.addChildNode(leftEyeNode)
            parentHUD.addChildNode(rightEyeNode)
            parentHUD.addChildNode(hudNode)
            
            hudOverlayNode = parentHUD
            
            if let faceNode = faceNode {
                faceNode.addChildNode(parentHUD)
            }
        }
        
        // MARK: - ARSCNViewDelegate
        
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let geometry = faceGeometry else { return }
            
            // Update geometry with the face shape
            geometry.update(from: faceAnchor.geometry)
            
            let mainNode = SCNNode(geometry: geometry)
            node.addChildNode(mainNode)
            faceNode = mainNode
            
            // Apply visual styles
            updateFaceStyle()
            
            Task { @MainActor in
                sessionModel.isFaceDetected = true
            }
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor else { return }
            
            // Update the mesh geometry mapping of the face in real-time
            faceGeometry?.update(from: faceAnchor.geometry)
            
            // If cyber HUD is active, we could rotate or shift HUD components slightly based on eye tracking or blink data
            if currentStyle == .cyberHUD, let hud = hudOverlayNode {
                // SCNTransaction to make adjustments smooth
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.1
                
                // Read face blends/blendShapes to detect winks or eye blinks
                let leftBlink = faceAnchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
                let rightBlink = faceAnchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0
                
                // Pulse or scale HUD targets on winking
                if let left = hud.childNodes.first {
                    left.scale = SCNVector3(1, 1, 1 - (leftBlink * 0.5))
                }
                if hud.childNodes.count > 1 {
                    let right = hud.childNodes[1]
                    right.scale = SCNVector3(1, 1, 1 - (rightBlink * 0.5))
                }
                
                SCNTransaction.commit()
            }
            
            Task { @MainActor in
                if !sessionModel.isFaceDetected {
                    sessionModel.isFaceDetected = true
                }
            }
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            guard anchor is ARFaceAnchor else { return }
            
            faceNode?.removeFromParentNode()
            faceNode = nil
            hudOverlayNode = nil
            
            Task { @MainActor in
                sessionModel.isFaceDetected = false
            }
        }
        
        // MARK: - ARSessionDelegate
        
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
        
        func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in
                sessionModel.isFaceDetected = false
            }
        }
    }
}
