import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import UIKit

/// Full-screen ARKit powered preview that lets users scrub through whitening intensities before capturing a photo.
struct LiveSmilePreviewView: View {
    enum CloseAction {
        case dismissOnly
        case fallbackToClassicCamera
    }
    
    let onCapture: (Data?) -> Void
    let onClose: (CloseAction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var whiteningAmount: CGFloat = 0.4
    @State private var captureSignal: Int = 0
    @State private var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    
    private var supportsFaceTracking: Bool {
        ARFaceTrackingConfiguration.isSupported
    }
    
    var body: some View {
        ZStack {
            if supportsFaceTracking && cameraAuthorization == .authorized {
                ARSmilePreviewCanvas(
                    whiteningAmount: $whiteningAmount,
                    captureSignal: $captureSignal,
                    onSnapshot: handleSnapshot(_:)
                )
                .ignoresSafeArea()
            } else {
                UnsupportedStateView(
                    supportsFaceTracking: supportsFaceTracking,
                    cameraAuthorization: cameraAuthorization,
                    requestPermission: requestCameraAccess,
                    triggerFallback: handleFallbackToClassicCamera
                )
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) {
            CloseButton {
                onClose(.dismissOnly)
                dismiss()
            }
            .padding(AppSpacing.m)
        }
        .overlay(alignment: .bottom) {
            if supportsFaceTracking && cameraAuthorization == .authorized {
                ControlsPanel(
                    whiteningAmount: $whiteningAmount,
                    capture: captureFrame
                )
            }
        }
        .background(Color.black)
        .task {
            requestCameraAccessIfNeeded()
        }
    }
    
    private func captureFrame() {
        captureSignal += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func handleFallbackToClassicCamera() {
        onClose(.fallbackToClassicCamera)
        dismiss()
    }
    
    private func handleSnapshot(_ image: UIImage?) {
        guard let image,
              let data = image.jpegData(compressionQuality: 0.84) else {
            onCapture(nil)
            onClose(.dismissOnly)
            dismiss()
            return
        }
        onCapture(data)
        onClose(.dismissOnly)
        dismiss()
    }
    
    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraAuthorization = granted ? .authorized : .denied
            }
        }
    }
    
    private func requestCameraAccessIfNeeded() {
        if cameraAuthorization == .notDetermined {
            requestCameraAccess()
        }
    }
}

// MARK: - Unsupported / Permission Views
private struct UnsupportedStateView: View {
    let supportsFaceTracking: Bool
    let cameraAuthorization: AVAuthorizationStatus
    let requestPermission: () -> Void
    let triggerFallback: () -> Void
    
    var body: some View {
        VStack(spacing: AppSpacing.l) {
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            
            VStack(spacing: AppSpacing.s) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, AppSpacing.l)
            }
            
            if cameraAuthorization == .notDetermined {
                Button("Enable Camera") {
                    requestPermission()
                }
                .buttonStyle(FloatingPrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.l)
            } else if cameraAuthorization == .denied {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(FloatingPrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.l)
            }
            
            Button("Use Classic Camera") {
                triggerFallback()
            }
            .buttonStyle(FloatingSecondaryButtonStyle())
            .padding(.horizontal, AppSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var title: String {
        if !supportsFaceTracking {
            return "AR Smile Preview Requires a TrueDepth Camera"
        }
        switch cameraAuthorization {
        case .authorized:
            return "Ready for Live Preview"
        case .denied, .restricted:
            return "Camera Access Needed"
        case .notDetermined:
            return "We Need Camera Access"
        @unknown default:
            return "Camera Access Needed"
        }
    }
    
    private var message: String {
        if !supportsFaceTracking {
            return "Try again on a device with a TrueDepth front camera to experience the live smile whitening preview."
        }
        switch cameraAuthorization {
        case .authorized:
            return "Hold tight while we prepare the live preview."
        case .denied, .restricted:
            return "Head to Settings → Gleam to enable camera access, or use the classic camera instead."
        case .notDetermined:
            return "We only use your camera for the AR preview. Grant access to continue."
        @unknown default:
            return "We only use your camera for the AR preview. Grant access to continue."
        }
    }
}

// MARK: - Controls Panel
private struct ControlsPanel: View {
    @Binding var whiteningAmount: CGFloat
    let capture: () -> Void
    
    var body: some View {
        VStack(spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Label("Whitening Intensity", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text(intensityLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                }
                Slider(value: $whiteningAmount, in: 0...1)
                    .tint(.white)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            
            Button(action: capture) {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "camera.aperture")
                        .font(.title2.weight(.semibold))
                    Text("Capture Smile")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                        .fill(Color.white)
                )
            }
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.bottom, AppSpacing.xl)
    }
    
    private var intensityLabel: String {
        "\(Int(whiteningAmount * 100))%"
    }
}

// MARK: - Close Button
private struct CloseButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.headline.weight(.semibold))
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.white)
        }
    }
}

// MARK: - AR Canvas
private struct ARSmilePreviewCanvas: UIViewRepresentable {
    @Binding var whiteningAmount: CGFloat
    @Binding var captureSignal: Int
    let onSnapshot: (UIImage?) -> Void
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.scene = SCNScene()
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateWhitening(to: whiteningAmount)
        context.coordinator.updateBoundsIfNeeded(uiView.bounds)
        if context.coordinator.consumeCaptureSignal(expected: captureSignal) {
            context.coordinator.captureSnapshot { image in
                onSnapshot(image)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    final class Coordinator: NSObject, ARSCNViewDelegate {
        private weak var sceneView: ARSCNView?
        private var faceNode: SCNNode?
        private var overlayLayer = CAShapeLayer()
        private var whiteningAmount: CGFloat = 0.4
        private var currentCaptureSignal: Int = 0
        private var mouthRect: CGRect = .zero
        private var hasValidRect = false
        
        func attach(to view: ARSCNView) {
            sceneView = view
            overlayLayer.fillColor = UIColor.white.cgColor
            overlayLayer.opacity = 0
            overlayLayer.shadowColor = UIColor.white.cgColor
            overlayLayer.shadowOpacity = 0.55
            overlayLayer.shadowOffset = .zero
            overlayLayer.compositingFilter = "screenBlendMode"
            view.layer.addSublayer(overlayLayer)
            startSession()
        }
        
        private func startSession() {
            guard ARFaceTrackingConfiguration.isSupported,
                  let sceneView else { return }
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        
        func updateBoundsIfNeeded(_ bounds: CGRect) {
            guard overlayLayer.frame != bounds else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlayLayer.frame = bounds
            CATransaction.commit()
        }
        
        func updateWhitening(to amount: CGFloat) {
            whiteningAmount = amount
            refreshOverlay()
        }
        
        func consumeCaptureSignal(expected: Int) -> Bool {
            guard expected != currentCaptureSignal else { return false }
            currentCaptureSignal = expected
            return true
        }
        
        func captureSnapshot(completion: @escaping (UIImage?) -> Void) {
            guard let view = sceneView else {
                completion(nil)
                return
            }
            DispatchQueue.main.async {
                let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
                let image = renderer.image { _ in
                    view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
                }
                completion(image)
            }
        }
        
        // MARK: - ARSCNViewDelegate
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let device = (renderer as? ARSCNView)?.device else { return nil }
            if let faceAnchor = anchor as? ARFaceAnchor {
                let faceGeometry = ARSCNFaceGeometry(device: device)
                faceGeometry?.firstMaterial?.fillMode = .lines
                faceGeometry?.firstMaterial?.transparency = 0.0
                let node = SCNNode(geometry: faceGeometry)
                faceNode = node
                return node
            }
            return nil
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor,
                  let geometry = node.geometry as? ARSCNFaceGeometry else {
                return
            }
            geometry.update(from: faceAnchor.geometry)
            updateMouthRect(with: faceAnchor)
        }
        
        private func updateMouthRect(with faceAnchor: ARFaceAnchor) {
            guard let sceneView else { return }
            var projectedPoints: [CGPoint] = []
            let vertices = faceAnchor.geometry.vertices
            for vertex in vertices where vertex.y > -0.08 && vertex.y < 0.05 && vertex.z > -0.05 {
                let scnPoint = SCNVector3(vertex)
                let projected = sceneView.projectPoint(scnPoint)
                if projected.z > 0,
                   projected.x.isFinite,
                   projected.y.isFinite {
                    projectedPoints.append(CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)))
                }
            }
            guard let minX = projectedPoints.map(\.x).min(),
                  let maxX = projectedPoints.map(\.x).max(),
                  let minY = projectedPoints.map(\.y).min(),
                  let maxY = projectedPoints.map(\.y).max(),
                  maxX > minX,
                  maxY > minY else {
                hasValidRect = false
                DispatchQueue.main.async { [weak self] in
                    self?.overlayLayer.opacity = 0
                }
                return
            }
            
            let rect = CGRect(
                x: minX - 18,
                y: minY - 12,
                width: (maxX - minX) + 36,
                height: (maxY - minY) + 26
            )
            mouthRect = rect
            hasValidRect = true
            refreshOverlay()
        }
        
        private func refreshOverlay() {
            guard hasValidRect else { return }
            let opacity = Float(0.15 + whiteningAmount * 0.75)
            let radius = mouthRect.height / 1.8
            let shadowRadius = 12 + whiteningAmount * 28
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            overlayLayer.path = UIBezierPath(
                roundedRect: mouthRect,
                cornerRadius: radius
            ).cgPath
            overlayLayer.opacity = opacity
            overlayLayer.shadowRadius = shadowRadius
            overlayLayer.fillColor = UIColor(
                white: 1.0,
                alpha: 0.55 + whiteningAmount * 0.35
            ).cgColor
            CATransaction.commit()
        }
    }
}

private extension SCNVector3 {
    init(_ simd: simd_float3) {
        self.init(simd.x, simd.y, simd.z)
    }
}
