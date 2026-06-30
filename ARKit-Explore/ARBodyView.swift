import SwiftUI
import ARKit
import SceneKit

struct ARBodyView: UIViewRepresentable {
    let sessionModel: ARSessionModel
    let resetTrigger: Int
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.automaticallyUpdatesLighting = true
        
        // Start the body tracking session
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
        
        private var bodyAnchor: ARBodyAnchor?
        private var jointSpheres: [String: SCNNode] = [:]
        private var connectionLines: [SCNNode] = []
        private var skeletonParentNode: SCNNode?
        
        // Define key joints we want to render in our skeleton
        private let keyJoints: [ARSkeleton.JointName] = [
            .root,
            .head,
            .leftShoulder,
            .rightShoulder,
            .leftHand,
            .rightHand,
            .leftFoot,
            .rightFoot
        ]
        
        // Connections between joints
        private let jointConnections: [(ARSkeleton.JointName, ARSkeleton.JointName)] = [
            (.root, .head),
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftHand),
            (.rightShoulder, .rightHand),
            (.root, .leftFoot),
            (.root, .rightFoot)
        ]
        
        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
        }
        
        func startSession(in arView: ARSCNView) {
            guard ARBodyTrackingConfiguration.isSupported else {
                Task { @MainActor in
                    sessionModel.errorMessage = "Body tracking is not supported on this device. Requires A12 chip or newer."
                }
                return
            }
            
            let configuration = ARBodyTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            Task { @MainActor in
                sessionModel.isSessionRunning = true
            }
        }
        
        func resetSession(in arView: ARSCNView) {
            clearSkeleton()
            startSession(in: arView)
            
            Task { @MainActor in
                sessionModel.isBodyDetected = false
            }
        }
        
        private func clearSkeleton() {
            skeletonParentNode?.removeFromParentNode()
            skeletonParentNode = nil
            jointSpheres.removeAll()
            
            for line in connectionLines {
                line.removeFromParentNode()
            }
            connectionLines.removeAll()
        }
        
        // MARK: - ARSCNViewDelegate
        
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { return }
            self.bodyAnchor = bodyAnchor
            
            // Create a parent node for skeleton
            let skeletonParent = SCNNode()
            node.addChildNode(skeletonParent)
            self.skeletonParentNode = skeletonParent
            
            // Create spheres for key joints
            let sphereGeometry = SCNSphere(radius: 0.04) // ~8cm diameter joint marker
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.8)
            material.specular.contents = UIColor.white
            material.shininess = 0.9
            material.emission.contents = UIColor.systemOrange.withAlphaComponent(0.9)
            sphereGeometry.materials = [material]
            
            for jointName in keyJoints {
                let jointNode = SCNNode(geometry: sphereGeometry)
                skeletonParent.addChildNode(jointNode)
                jointSpheres[jointName.rawValue] = jointNode
            }
            
            updateJointPositions()
            
            Task { @MainActor in
                sessionModel.isBodyDetected = true
            }
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { return }
            self.bodyAnchor = bodyAnchor
            
            updateJointPositions()
            
            Task { @MainActor in
                if !sessionModel.isBodyDetected {
                    sessionModel.isBodyDetected = true
                }
            }
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            guard anchor is ARBodyAnchor else { return }
            
            clearSkeleton()
            
            Task { @MainActor in
                sessionModel.isBodyDetected = false
            }
        }
        
        private func updateJointPositions() {
            guard let bodyAnchor = bodyAnchor else { return }
            let skeleton = bodyAnchor.skeleton
            
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.05 // Interpolate frames for smoother movements
            
            for jointName in keyJoints {
                let jointNameStr = jointName.rawValue
                
                // Get the local transform of the joint in relation to the model anchor
                if let modelTransform = skeleton.modelTransform(for: jointName) {
                    // Extract position vector from matrix
                    let col3 = modelTransform.columns.3
                    let position = SCNVector3(col3.x, col3.y, col3.z)
                    
                    if let jointNode = jointSpheres[jointNameStr] {
                        jointNode.position = position
                    }
                }
            }
            
            updateConnectionLines()
            
            SCNTransaction.commit()
        }
        
        private func updateConnectionLines() {
            // Remove old lines
            for line in connectionLines {
                line.removeFromParentNode()
            }
            connectionLines.removeAll()
            
            guard let skeletonParent = skeletonParentNode else { return }
            
            // Build new connection lines
            for (j1, j2) in jointConnections {
                guard let node1 = jointSpheres[j1.rawValue],
                      let node2 = jointSpheres[j2.rawValue] else { continue }
                
                let lineNode = cylinderLine(from: node1.position, to: node2.position, radius: 0.012, color: .systemOrange)
                skeletonParent.addChildNode(lineNode)
                connectionLines.append(lineNode)
            }
        }
        
        private func cylinderLine(from v1: SCNVector3, to v2: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
            let dx = v2.x - v1.x
            let dy = v2.y - v1.y
            let dz = v2.z - v1.z
            let distance = sqrt(dx*dx + dy*dy + dz*dz)
            
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.8)
            cylinder.materials = [material]
            
            let node = SCNNode(geometry: cylinder)
            node.position = SCNVector3(v1.x + dx/2, v1.y + dy/2, v1.z + dz/2)
            
            let direction = SCNVector3(dx, dy, dz)
            let yAxis = SCNVector3(0, 1, 0)
            
            let length = Float(distance)
            if length > 0 {
                let normalizedDirection = SCNVector3(direction.x / length, direction.y / length, direction.z / length)
                
                let rotationAxis = SCNVector3(
                    yAxis.y * normalizedDirection.z - yAxis.z * normalizedDirection.y,
                    yAxis.z * normalizedDirection.x - yAxis.x * normalizedDirection.z,
                    yAxis.x * normalizedDirection.y - yAxis.y * normalizedDirection.x
                )
                
                let dotProduct = yAxis.x * normalizedDirection.x + yAxis.y * normalizedDirection.y + yAxis.z * normalizedDirection.z
                let angle = acos(dotProduct)
                
                let axisLength = sqrt(rotationAxis.x*rotationAxis.x + rotationAxis.y*rotationAxis.y + rotationAxis.z*rotationAxis.z)
                if axisLength > 0.0001 {
                    let normalizedAxis = SCNVector3(rotationAxis.x / axisLength, rotationAxis.y / axisLength, rotationAxis.z / axisLength)
                    node.rotation = SCNVector4(normalizedAxis.x, normalizedAxis.y, normalizedAxis.z, angle)
                }
            }
            
            return node
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
                sessionModel.isBodyDetected = false
            }
        }
    }
}
