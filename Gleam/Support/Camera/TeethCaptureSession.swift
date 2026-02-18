import AVFoundation
import Combine
import CoreImage
import ImageIO
import SwiftUI
import UIKit

struct TeethCaptureSession: View {
    let onCapture: (Data, CIImage?) -> Void
    let onCancel: () -> Void

    @StateObject private var cameraController = TeethCameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraController.authorizationDenied {
                permissionFallback
            } else {
                TeethCameraPreview(session: cameraController.session)
                    .ignoresSafeArea()

                if !cameraController.isSessionReady {
                    ProgressView("Preparing camera...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }

                controlsOverlay
            }
        }
        .task {
            await cameraController.prepareSession()
        }
        .onDisappear {
            cameraController.stopSession()
        }
        .alert(
            "Camera unavailable",
            isPresented: Binding(
                get: { cameraController.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        cameraController.errorMessage = nil
                    }
                }
            )
        ) {
            Button("Close") {
                onCancel()
            }
        } message: {
            Text(cameraController.errorMessage ?? "Unable to start camera.")
        }
    }

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.leading, 20)
                .padding(.top, 20)

                Spacer()
            }

            Spacer()

            VStack(spacing: 12) {
                if !cameraController.supportsTeethMatte {
                    Text("Teeth segmentation is unavailable on this camera.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Button {
                    cameraController.capturePhoto { data, matte in
                        onCapture(data, matte)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 74, height: 74)
                        Circle()
                            .stroke(Color.black.opacity(0.15), lineWidth: 2)
                            .frame(width: 66, height: 66)
                    }
                }
                .disabled(!cameraController.isSessionReady || cameraController.isCapturing)
                .opacity(cameraController.isSessionReady ? 1.0 : 0.5)
            }
            .padding(.bottom, 36)
        }
    }

    private var permissionFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.85))
            Text("Camera access is required to take a photo.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enable camera permission in Settings, then try again.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Close") {
                onCancel()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct TeethCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        view.previewLayer.connection?.isVideoMirrored = true
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        uiView.previewLayer.connection?.isVideoMirrored = true
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}

private final class TeethCameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isSessionReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var authorizationDenied = false
    @Published private(set) var supportsTeethMatte = false
    @Published var errorMessage: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.gleam.teeth-camera.session")
    private var didConfigureSession = false
    private var captureCompletion: ((Data, CIImage?) -> Void)?

    @MainActor
    func prepareSession() async {
        if didConfigureSession {
            startSessionIfNeeded()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
            }
            if !granted {
                authorizationDenied = true
                return
            }
        case .denied, .restricted:
            authorizationDenied = true
            return
        @unknown default:
            authorizationDenied = true
            return
        }

        await configureSession()
    }

    @MainActor
    func capturePhoto(onCapture: @escaping (Data, CIImage?) -> Void) {
        guard isSessionReady, !isCapturing else { return }
        isCapturing = true
        captureCompletion = onCapture

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        // Some front camera configurations only allow .speed or .balanced.
        // Passing a higher value than supported crashes with NSInvalidArgumentException.
        settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization
        settings.isHighResolutionPhotoEnabled = photoOutput.isHighResolutionCaptureEnabled
        if supportsTeethMatte {
            settings.enabledSemanticSegmentationMatteTypes = [.teeth]
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func startSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    @MainActor
    private func configureSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }

                let cameraDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

                guard let device = cameraDevice else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.errorMessage = "No front camera is available on this device."
                        continuation.resume()
                    }
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        DispatchQueue.main.async {
                            self.errorMessage = "Unable to configure camera input."
                            continuation.resume()
                        }
                        return
                    }
                    self.session.addInput(input)
                } catch {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.errorMessage = "Unable to access camera input."
                        continuation.resume()
                    }
                    return
                }

                guard self.session.canAddOutput(self.photoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.errorMessage = "Unable to configure photo capture."
                        continuation.resume()
                    }
                    return
                }

                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true

                let matteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                let supportsTeethMatte = matteTypes.contains(.teeth)
                if supportsTeethMatte {
                    self.photoOutput.enabledSemanticSegmentationMatteTypes = [.teeth]
                }

                self.session.commitConfiguration()
                self.session.startRunning()
                self.didConfigureSession = true

                DispatchQueue.main.async {
                    self.supportsTeethMatte = supportsTeethMatte
                    self.isSessionReady = true
                    continuation.resume()
                }
            }
        }
    }
}

extension TeethCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if error != nil {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.errorMessage = "Could not capture photo. Please try again."
                self.captureCompletion = nil
            }
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.errorMessage = "Could not process captured image."
                self.captureCompletion = nil
            }
            return
        }

        var matteImage: CIImage?
        if let matte = photo.semanticSegmentationMatte(for: .teeth) {
            let orientationValue = (photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32) ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            let orientedMatte = matte.applyingExifOrientation(orientation)
            matteImage = CIImage(cvPixelBuffer: orientedMatte.mattingImage)
        }

        DispatchQueue.main.async {
            self.isCapturing = false
            self.captureCompletion?(imageData, matteImage)
            self.captureCompletion = nil
        }
    }
}
