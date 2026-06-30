import SwiftUI
import ARKit

struct ContentView: View {
    @State private var activeModule: ARModule? = nil
    @State private var sessionModel = ARSessionModel()
    
    // Config state passed to AR views
    @State private var selectedShape: ARPlaneView.PlacementShape = .torus
    @State private var selectedFaceStyle: ARFaceView.FaceStyle = .wireframe
    @State private var resetTrigger = 0
    
    // Background animation states for the dashboard
    @State private var animateGlow = false
    
    enum ARModule: String, CaseIterable, Identifiable {
        case plane = "Plane Detection"
        case face = "Face Geometry"
        case body = "Body Tracking"
        case hand = "Vision Hand Pose"
        case coreML = "CoreML Classifier"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .plane: return "square.stack.3d.down.right"
            case .face: return "face.smiling"
            case .body: return "figure.walk"
            case .hand: return "hand.raised"
            case .coreML: return "brain"
            }
        }
        
        var description: String {
            switch self {
            case .plane: return "Map surrounding surfaces. Tap to place floating neon geometry."
            case .face: return "Track real-time expressions & map coordinates with front TrueDepth camera."
            case .body: return "Estimate 3D skeletal joint vectors and track body kinematics."
            case .hand: return "Perform hand landmark tracking and overlay glowing wireframes using Vision."
            case .coreML: return "Detect objects via CoreML/Vision and anchor holographic tags on top of them."
            }
        }
        
        var themeColor: Color {
            switch self {
            case .plane: return .teal
            case .face: return .cyan
            case .body: return .orange
            case .hand: return .purple
            case .coreML: return .green
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Futuristic dark cosmic background
                Color.black.ignoresSafeArea()
                
                // Animated neon mesh lights
                RadialGradient(
                    colors: [Color.purple.opacity(0.18), Color.clear],
                    center: animateGlow ? .topLeading : .bottomTrailing,
                    startRadius: 50,
                    endRadius: 400
                )
                .ignoresSafeArea()
                .animation(.linear(duration: 10).repeatForever(autoreverses: true), value: animateGlow)
                
                RadialGradient(
                    colors: [Color.teal.opacity(0.12), Color.clear],
                    center: animateGlow ? .bottomTrailing : .topLeading,
                    startRadius: 50,
                    endRadius: 400
                )
                .ignoresSafeArea()
                .animation(.linear(duration: 12).repeatForever(autoreverses: true), value: animateGlow)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        
                        // Header Group
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AR SPATIAL EXPLORER")
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .white.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .tracking(4)
                                .accessibilityHeading(.h1)
                            
                            Text("iPhone 17 iOS 26+ High-Fidelity Showcase")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 24)
                        
                        // Status Panel with iOS 26 Liquid Glass
                        statusPanel
                        
                        // Module Grid
                        Text("SHOWCASE MODULES")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(2)
                            .padding(.top, 10)
                        
                        VStack(spacing: 20) {
                            ForEach(ARModule.allCases) { module in
                                moduleCard(for: module)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarBackButtonHidden()
            .onAppear {
                animateGlow = true
            }
            .fullScreenCover(item: $activeModule) { module in
                moduleContainerView(for: module)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Dashboard Subviews
    
    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(sessionModel.isSessionRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(sessionModel.isSessionRunning ? "SYSTEM ACTIVE" : "SYSTEM STANDBY")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            
            Text("Engine Status: \(sessionModel.trackingStateText)")
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(.all, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffectWithFallback(in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func moduleCard(for module: ARModule) -> some View {
        Button {
            sessionModel.reset()
            activeModule = module
        } label: {
            HStack(spacing: 18) {
                Image(systemName: module.icon)
                    .font(.title)
                    .foregroundStyle(module.themeColor)
                    .frame(width: 54, height: 54)
                    .background(module.themeColor.opacity(0.15), in: .circle)
                    .overlay(
                        Circle().stroke(module.themeColor.opacity(0.3), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(module.rawValue)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text(module.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.all, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffectWithFallback(in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [module.themeColor.opacity(0.25), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - AR Presenter Container
    
    private func moduleContainerView(for module: ARModule) -> some View {
        ZStack {
            // Live AR view
            switch module {
            case .plane:
                ARPlaneView(sessionModel: sessionModel, placementObjectShape: selectedShape, resetTrigger: resetTrigger)
                    .ignoresSafeArea()
            case .face:
                ARFaceView(sessionModel: sessionModel, selectedStyle: selectedFaceStyle, resetTrigger: resetTrigger)
                    .ignoresSafeArea()
            case .body:
                ARBodyView(sessionModel: sessionModel, resetTrigger: resetTrigger)
                    .ignoresSafeArea()
            case .hand:
                ARHandView(sessionModel: sessionModel, resetTrigger: resetTrigger)
                    .ignoresSafeArea()
            case .coreML:
                ARObjectTaggingView(sessionModel: sessionModel, resetTrigger: resetTrigger)
                    .ignoresSafeArea()
            }
            
            // HUD & Control Overlays
            VStack {
                
                // Top floating status bar
                HStack(alignment: .top) {
                    // Floating Back Button
                    Button {
                        activeModule = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .interactiveGlassEffectWithFallback(in: .circle)
                    .accessibilityLabel("Back to Dashboard")
                    
                    Spacer()
                    
                    // Live telemetry readouts
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(module.rawValue.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(module.themeColor)
                        
                        Text(sessionModel.trackingStateText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        // Detail telemetry based on module
                        Group {
                            switch module {
                            case .plane:
                                Text("Planes: \(sessionModel.detectedPlanesCount)")
                            case .face:
                                Text("Face Detected: \(sessionModel.isFaceDetected ? "YES" : "NO")")
                            case .body:
                                Text("Body Detected: \(sessionModel.isBodyDetected ? "YES" : "NO")")
                            case .hand:
                                Text("Hand Detected: \(sessionModel.isHandDetected ? "YES" : "NO")")
                            case .coreML:
                                Text("Object: \(sessionModel.isObjectDetected ? sessionModel.detectedObjectName : "Searching...")")
                            }
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffectWithFallback(in: .rect(cornerRadius: 12))
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Error toast banner
                if let error = sessionModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85), in: .capsule)
                        .padding(.bottom, 12)
                        .onAppear {
                            // Automatically clear error after 4 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                sessionModel.errorMessage = nil
                            }
                        }
                }
                
                // Bottom control dock
                VStack(spacing: 16) {
                    
                    // Inline context controls (if applicable)
                    Group {
                        switch module {
                        case .plane:
                            pickerControls(
                                title: "Placement Shape",
                                selection: $selectedShape,
                                items: ARPlaneView.PlacementShape.allCases
                            )
                        case .face:
                            pickerControls(
                                title: "Mesh Style",
                                selection: $selectedFaceStyle,
                                items: ARFaceView.FaceStyle.allCases
                            )
                        case .body, .hand, .coreML:
                            EmptyView()
                        }
                    }
                    
                    // Standard action dock using iOS 26 Liquid Glass grouped buttons
                    HStack {
                        Button {
                            resetTrigger += 1
                        } label: {
                            Label("Reset Session", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                        }
                        .interactiveGlassEffectWithFallback(in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Picker Subview
    
    private func pickerControls<T: Hashable & RawRepresentable>(
        title: String,
        selection: Binding<T>,
        items: [T]
    ) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.5)
                .padding(.leading, 8)
            
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            Button(item.rawValue) {
                                selection.wrappedValue = item
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(selection.wrappedValue == item ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(
                                selection.wrappedValue == item
                                    ? .regular.tint(.white.opacity(0.2)).interactive()
                                    : .clear.interactive(),
                                in: .capsule
                            )
                        }
                    }
                    .padding(4)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Button(item.rawValue) {
                            selection.wrappedValue = item
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selection.wrappedValue == item
                                ? Color.white.opacity(0.22)
                                : Color.white.opacity(0.08),
                            in: .capsule
                        )
                    }
                }
                .padding(4)
                .background(.ultraThinMaterial, in: .capsule)
            }
        }
    }
}

// MARK: - View Modifiers for Glass Effects

extension View {
    @ViewBuilder
    func glassEffectWithFallback(
        in shape: some Shape = .rect,
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(fallbackMaterial, in: shape)
        }
    }
    
    @ViewBuilder
    func interactiveGlassEffectWithFallback(
        in shape: some Shape = .capsule,
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(fallbackMaterial, in: shape)
        }
    }
}

#Preview {
    ContentView()
}
