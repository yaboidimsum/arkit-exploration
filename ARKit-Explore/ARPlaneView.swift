import SwiftUI
import ARKit
import SceneKit

struct ARPlaneView: UIViewRepresentable {
    let sessionModel: ARSessionModel
    let placementObjectShape: PlacementShape
    let resetTrigger: Int
    
    enum PlacementShape: String, CaseIterable, Identifiable {
        case sphere = "Sphere"
        case box = "Box"
        case torus = "Torus"
        case pyramid = "Pyramid"
        
        var id: String { self.rawValue }
    }
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        arView.showsStatistics = false
        
        // Add tap gesture for object placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        // Configure and start session
        context.coordinator.startSession(in: arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Handle reset
        if context.coordinator.lastResetTrigger != resetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            context.coordinator.resetPlanesAndObjects(in: uiView)
        }
        
        // Pass the currently selected shape to the coordinator
        context.coordinator.placementObjectShape = placementObjectShape
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(sessionModel: sessionModel, placementObjectShape: placementObjectShape)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let sessionModel: ARSessionModel
        var placementObjectShape: PlacementShape
        var lastResetTrigger = 0
        
        // Map to keep track of plane nodes
        private var planeNodes: [ARPlaneAnchor: SCNNode] = [:]
        private var placedObjects: [SCNNode] = []
        
        init(sessionModel: ARSessionModel, placementObjectShape: PlacementShape) {
            self.sessionModel = sessionModel
            self.placementObjectShape = placementObjectShape
        }
        
        func startSession(in arView: ARSCNView) {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.isLightEstimationEnabled = true
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            Task { @MainActor in
                sessionModel.isSessionRunning = true
            }
        }
        
        func resetPlanesAndObjects(in arView: ARSCNView) {
            // Remove placed objects
            for node in placedObjects {
                node.removeFromParentNode()
            }
            placedObjects.removeAll()
            
            // Remove planes
            for (_, node) in planeNodes {
                node.removeFromParentNode()
            }
            planeNodes.removeAll()
            
            // Restart tracking
            startSession(in: arView)
            
            Task { @MainActor in
                sessionModel.detectedPlanesCount = 0
            }
        }
        
        // MARK: - ARSCNViewDelegate
        
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            
            // Create a plane node to visualize the detected surface
            let planeGeometry = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
            
            // Bright styling for planes (glowing green)
            let gridMaterial = SCNMaterial()
            gridMaterial.diffuse.contents = UIColor.green.withAlphaComponent(0.25)
            gridMaterial.emission.contents = UIColor.green
            gridMaterial.isDoubleSided = true
            planeGeometry.materials = [gridMaterial]
            
            let planeNode = SCNNode(geometry: planeGeometry)
            planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
            // SCNPlane is vertical by default, rotate it to horizontal
            planeNode.eulerAngles.x = -.pi / 2
            
            // Add a thin border or overlay pattern if needed
            node.addChildNode(planeNode)
            planeNodes[planeAnchor] = planeNode
            
            Task { @MainActor in
                sessionModel.detectedPlanesCount = planeNodes.count
            }
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor,
                  let planeNode = planeNodes[planeAnchor],
                  let planeGeometry = planeNode.geometry as? SCNPlane else { return }
            
            // Update plane size and position
            planeGeometry.width = CGFloat(planeAnchor.extent.x)
            planeGeometry.height = CGFloat(planeAnchor.extent.z)
            planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            guard let planeAnchor = anchor as? ARPlaneAnchor,
                  let planeNode = planeNodes[planeAnchor] else { return }
            
            planeNode.removeFromParentNode()
            planeNodes.removeValue(forKey: planeAnchor)
            
            Task { @MainActor in
                sessionModel.detectedPlanesCount = planeNodes.count
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
        
        // MARK: - Tap Handling & Placement
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARSCNView else { return }
            let tapLocation = gesture.location(in: arView)
            
            // Perform raycast
            let query = arView.raycastQuery(from: tapLocation, allowing: .estimatedPlane, alignment: .any)
            guard let raycastQuery = query else { return }
            
            let results = arView.session.raycast(raycastQuery)
            if let firstResult = results.first {
                let transform = firstResult.worldTransform
                let position = SCNVector3(
                    transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z
                )
                placeObject(at: position, in: arView.scene.rootNode)
            }
        }
        
        private func placeObject(at position: SCNVector3, in rootNode: SCNNode) {
            let geometry: SCNGeometry
            let scale: Float = 0.08
            
            // Create geometric shape based on selection
            switch placementObjectShape {
            case .sphere:
                geometry = SCNSphere(radius: CGFloat(scale))
            case .box:
                geometry = SCNBox(width: CGFloat(scale), height: CGFloat(scale), length: CGFloat(scale), chamferRadius: 0.01)
            case .torus:
                geometry = SCNTorus(ringRadius: CGFloat(scale), pipeRadius: CGFloat(scale * 0.3))
            case .pyramid:
                geometry = SCNPyramid(width: CGFloat(scale), height: CGFloat(scale), length: CGFloat(scale))
            }
            
            // Solid opaque materials with distinct colors per shape
            let material = SCNMaterial()
            let color: UIColor
            switch placementObjectShape {
            case .sphere:
                color = UIColor.systemOrange
            case .box:
                color = UIColor.systemBlue
            case .torus:
                color = UIColor.systemPink
            case .pyramid:
                color = UIColor.systemYellow
            }
            material.diffuse.contents = color
            material.roughness.contents = 0.2
            material.metalness.contents = 0.8
            material.specular.contents = UIColor.white
            material.shininess = 0.9
            material.emission.contents = color.withAlphaComponent(0.35)
            geometry.materials = [material]
            
            let node = SCNNode(geometry: geometry)
            node.position = position
            
            // Add subtle entry animation (scaling up)
            node.scale = SCNVector3(0, 0, 0)
            rootNode.addChildNode(node)
            placedObjects.append(node)
            
            // Animate scale and rotation
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            node.scale = SCNVector3(1, 1, 1)
            SCNTransaction.commit()
            
            // Continuous spinning and hovering animation
            let rotateAction = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4)
            let repeatRotate = SCNAction.repeatForever(rotateAction)
            
            let hoverUp = SCNAction.moveBy(x: 0, y: 0.02, z: 0, duration: 1.5)
            hoverUp.timingMode = .easeInEaseOut
            let hoverDown = SCNAction.moveBy(x: 0, y: -0.02, z: 0, duration: 1.5)
            hoverDown.timingMode = .easeInEaseOut
            let hoverSequence = SCNAction.sequence([hoverUp, hoverDown])
            let repeatHover = SCNAction.repeatForever(hoverSequence)
            
            node.runAction(repeatRotate)
            node.runAction(repeatHover)
        }
    }
}
