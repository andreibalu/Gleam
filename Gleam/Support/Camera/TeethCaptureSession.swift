import AVFoundation
import Combine
import CoreImage
import SwiftUI
import UIKit

struct CaptureResult {
  let imageData: Data
  let teethMatte: CIImage?
}

final class TeethCaptureSession: NSObject, ObservableObject {
  @Published var isSessionRunning = false
  @Published var captureResult: CaptureResult?
  @Published var permissionDenied = false

  let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private var completion: ((CaptureResult?) -> Void)?

  func configure() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      setupSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.setupSession()
          } else {
            self?.permissionDenied = true
          }
        }
      }
    default:
      DispatchQueue.main.async { self.permissionDenied = true }
    }
  }

  func startRunning() {
    guard !session.isRunning else { return }
    DispatchQueue.global(qos: .userInitiated).async { [session] in
      session.startRunning()
      DispatchQueue.main.async { self.isSessionRunning = true }
    }
  }

  func stopRunning() {
    guard session.isRunning else { return }
    DispatchQueue.global(qos: .userInitiated).async { [session] in
      session.stopRunning()
      DispatchQueue.main.async { self.isSessionRunning = false }
    }
  }

  func capturePhoto(completion: @escaping (CaptureResult?) -> Void) {
    self.completion = completion
    let settings = AVCapturePhotoSettings()
    settings.enabledSemanticSegmentationMatteTypes =
      photoOutput.availableSemanticSegmentationMatteTypes.filter { $0 == .teeth }
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  // MARK: - Private

  private func setupSession() {
    session.beginConfiguration()
    session.sessionPreset = .photo

    let device = AVCaptureDevice.default(
      .builtInTrueDepthCamera, for: .video, position: .front
    ) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

    guard let device,
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      session.commitConfiguration()
      return
    }
    session.addInput(input)

    guard session.canAddOutput(photoOutput) else {
      session.commitConfiguration()
      return
    }
    session.addOutput(photoOutput)

    photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
    let availableMattes = photoOutput.availableSemanticSegmentationMatteTypes
    print("[TeethCapture] Setup - depth supported: \(photoOutput.isDepthDataDeliverySupported)")
    print("[TeethCapture] Setup - available matte types: \(availableMattes)")
    photoOutput.enabledSemanticSegmentationMatteTypes =
      availableMattes.filter { $0 == .teeth }
    print("[TeethCapture] Setup - enabled matte types: \(photoOutput.enabledSemanticSegmentationMatteTypes)")

    session.commitConfiguration()
    startRunning()
  }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension TeethCaptureSession: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    guard error == nil, let imageData = photo.fileDataRepresentation() else {
      DispatchQueue.main.async { self.completion?(nil) }
      return
    }

    let compressedData = compressImage(imageData)
    let teethMatte: CIImage? = {
      guard let matte = photo.semanticSegmentationMatte(for: .teeth) else {
        print("[TeethCapture] Teeth matte NOT available in this capture")
        return nil
      }
      print("[TeethCapture] Teeth matte captured successfully")
      return CIImage(cvPixelBuffer: matte.mattingImage)
    }()

    let result = CaptureResult(
      imageData: compressedData ?? imageData,
      teethMatte: teethMatte
    )
    DispatchQueue.main.async {
      self.captureResult = result
      self.completion?(result)
    }
  }

  private func compressImage(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let maxDimension: CGFloat = 1024
    let size = image.size
    let scale = min(1, maxDimension / max(size.width, size.height))
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    UIGraphicsBeginImageContextWithOptions(newSize, true, 1)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let scaled = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return scaled?.jpegData(compressionQuality: 0.7)
  }
}

// MARK: - SwiftUI Preview Layer

struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(layer)
    context.coordinator.previewLayer = layer
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async {
      context.coordinator.previewLayer?.frame = uiView.bounds
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var previewLayer: AVCaptureVideoPreviewLayer?
  }
}

// MARK: - Teeth Camera View (full-screen camera UI)

struct TeethCameraView: View {
  @StateObject private var captureSession = TeethCaptureSession()
  let onCapture: (CaptureResult?) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      if captureSession.permissionDenied {
        permissionDeniedView
      } else {
        CameraPreviewView(session: captureSession.session)
          .ignoresSafeArea()

        VStack {
          HStack {
            Button {
              captureSession.stopRunning()
              onCapture(nil)
            } label: {
              Image(systemName: "xmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(Circle().fill(.ultraThinMaterial))
            }
            Spacer()
          }
          .padding(.horizontal)
          .padding(.top, 8)

          Spacer()

          shutterButton
            .padding(.bottom, 40)
        }
      }
    }
    .onAppear { captureSession.configure() }
    .onDisappear { captureSession.stopRunning() }
    .statusBarHidden(true)
  }

  private var shutterButton: some View {
    Button {
      captureSession.capturePhoto { result in
        captureSession.stopRunning()
        onCapture(result)
      }
    } label: {
      ZStack {
        Circle()
          .stroke(.white, lineWidth: 4)
          .frame(width: 72, height: 72)
        Circle()
          .fill(.white)
          .frame(width: 60, height: 60)
      }
    }
  }

  private var permissionDeniedView: some View {
    VStack(spacing: AppSpacing.m) {
      Image(systemName: "camera.fill")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text("Camera Access Required")
        .font(.title3.weight(.semibold))
      Text("Please allow camera access in Settings to take teeth photos.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      .buttonStyle(.borderedProminent)

      Button("Cancel") {
        onCapture(nil)
      }
      .foregroundStyle(.secondary)
    }
    .padding()
  }
}

