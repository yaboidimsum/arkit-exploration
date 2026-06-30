# ARKit-Explore: SwiftUI Spatial Computing Showcase

An advanced, premium iOS showcase application demonstrating high-fidelity **ARKit** capabilities combined with the **Vision** framework and **CoreML** image classification. The application is built using SwiftUI and SceneKit, adopting Apple's modern **iOS 26+ Liquid Glass** design language while remaining backwards-compatible down to iOS 17.0+.

---

## 🚀 Features

### 1. Plane Detection & Placement
*   **Real-time Mapping**: Maps horizontal and vertical planes, displaying them as high-visibility, glowing neon-green overlays.
*   **Solid Geometry Placement**: Tap anywhere on a detected surface to spawn 3D objects with solid, metallic shaders and shape-specific color coding:
    *   🟢 **Sphere**: Solid Neon Orange
    *   🔵 **Box**: Solid Neon Blue
    *   🟣 **Torus**: Solid Neon Magenta
    *   🟡 **Pyramid**: Solid Neon Yellow
*   **Micro-Animations**: Placed geometries continuously rotate and hover vertically using smooth `SCNAction` curves.

### 2. Face Geometry & Cyber HUD
*   **TrueDepth Tracking**: Leverages front-facing TrueDepth cameras to generate high-density face meshes.
*   **Three Visual Styles**:
    *   **Sci-Fi Grid**: A cybernetic wireframe overlay outlining facial topology.
    *   **Neon Hologram**: A purple/teal translucent metallic mask mapping expressions.
    *   **Cyber HUD**: Places tracking rings on eyes and a forehead HUD board. Using ARKit's blendshapes, winking or blinking scales and compresses HUD rings in real time.

### 3. 3D Body Skeleton Tracking
*   **Kinematic Tracking**: Resolves 3D positions of 8 key skeletal joints (root, head, left/right shoulders, left/right hands, left/right feet).
*   **Glowing Wireframe**: Connects joints together in 3D space using orange cylinder vector nodes. Includes orientation alignment math and SCNTransaction animations to eliminate jitter.

### 4. Vision Hand Pose Estimation
*   **Normalized Landmark Detection**: Runs `VNDetectHumanHandPoseRequest` on a concurrent background queue to track 21 coordinates on the hand.
*   **Natural 1-to-1 Mirroring**: Coordinates are horizontally flipped (`1.0 - normalizedViewportPoint.x`) before being projected to match screen movements naturally.
*   **Fluid Visuals**: Draws a glowing cyan skeletal hand outline and white nodes on a SwiftUI `Canvas` overlay at 60 FPS.

### 5. CoreML Object Tagging
*   **No ML Training Needed**: Utilizes Apple's built-in image classification models (`VNClassifyImageRequest`) to categorize real-world items (e.g. computer, cup, keyboard, mouse).
*   **Salient Cropping**: Integrates `VNGenerateAttentionBasedSaliencyImageRequest` to isolate classifications to the most prominent focal objects.
*   **Feature-Point Anchoring**: Uses `arView.hitTest` against `.featurePoint` point clouds to drop a 3D tag directly on the object's surface (rather than just flat floors).
*   **Tag Design**: Renders a bold 2D bounding square overlay (`SCNPlane` with a custom `16pt` border outline) around the object, with a large, highly legible billboarded 3D text showing the name and percentage (e.g., `Laptop (85%)`).
*   **Camera-Forward Fallback**: If plane tracking hasn't resolved surface vectors yet, the tag floats 0.5m directly in front of the lens.

---

## 🛠 Technology Stack

*   **Swift UI**: Built using iOS 17+ state flow (`@Observable`, `@MainActor` thread safety, `.sensoryFeedback`, `.onChange(of:initial:)`).
*   **ARKit**: High-level world tracking, face mapping, body tracking, and display transform mapping.
*   **Vision & CoreML**: Concurrent saliency estimation, hand pose recognition, and built-in image classification.
*   **SceneKit**: 3D scene graph rendering, custom geometry generation, custom shaders, and billboard constraints.
*   **Liquid Glass (iOS 26+)**: Adopts `.glassEffect()`, `.interactive()`, and `GlassEffectContainer` for a premium translucent spatial UI, falling back to `.ultraThinMaterial` on iOS 17.

---

## 📱 Getting Started

### Requirements
*   **Xcode**: Xcode 15+ (Xcode 26+ required to compile Liquid Glass effects).
*   **iOS Target**: iOS 17.0+ (iOS 26.0+ recommended).
*   **Device**: Physical iPhone/iPad with an A12 Bionic chip or newer (for Neural Engine acceleration on Vision models) and a TrueDepth camera system (for face tracking).

### Camera Access Setup
Camera usage descriptions are pre-configured inside the [project.pbxproj](ARKit-Explore.xcodeproj/project.pbxproj) file:
*   `INFOPLIST_KEY_NSCameraUsageDescription` = `"This app requires camera access for augmented reality tracking showcases."`

---

## 📂 Architecture

*   [ARKit_ExploreApp.swift](ARKit-Explore/ARKit_ExploreApp.swift): Main SwiftUI app entry point.
*   [ContentView.swift](ARKit-Explore/ContentView.swift): Premium control center dashboard styling, radial gradients, navigation, and Liquid Glass wrapper sheets.
*   [ARSessionModel.swift](ARKit-Explore/ARSessionModel.swift): Unified telemetry state coordinator for tracking events, errors, and counts.
*   [ARPlaneView.swift](ARKit-Explore/ARPlaneView.swift): Presenter for surface mapping and shape placement.
*   [ARFaceView.swift](ARKit-Explore/ARFaceView.swift): Presenter for TrueDepth facial meshes and eye blendshapes.
*   [ARBodyView.swift](ARKit-Explore/ARBodyView.swift): Presenter for body tracking and cylinder bone connections.
*   [ARHandView.swift](ARKit-Explore/ARHandView.swift): Presenter for Vision hand pose coordinates and Canvas drawing.
*   [ARObjectTaggingView.swift](ARKit-Explore/ARObjectTaggingView.swift): Presenter for CoreML classifications, saliency cropping, feature-point hit-testing, and dynamic bold border rendering.
# arkit-exploration
