import AVFoundation
import ImageIO
import SwiftUI
import UIKit

struct TeethMatteCaptureView: UIViewControllerRepresentable {
    let onCapture: (TeethPlaygroundSample) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> TeethMatteCameraViewController {
        let controller = TeethMatteCameraViewController()
        controller.onCapture = onCapture
        controller.onCancel = onCancel
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: TeethMatteCameraViewController, context: Context) {}
}

final class TeethMatteCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((TeethPlaygroundSample) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.gleam.playground.teeth.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let overlayGradient = CAGradientLayer()

    private let previewContainer = UIView()
    private let matteStatusLabel = UILabel()
    private let captureButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var sessionConfigured = false
    private var teethMatteSupported = false
    private let logPrefix = "[TeethPlaygroundCamera]"

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        requestPermissionAndConfigureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = previewContainer.bounds
        overlayGradient.frame = previewContainer.bounds
    }

    private func configureUI() {
        view.backgroundColor = .black

        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)
        NSLayoutConstraint.activate([
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewContainer.layer.addSublayer(previewLayer)

        overlayGradient.colors = [
            UIColor.black.withAlphaComponent(0.65).cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.65).cgColor
        ]
        overlayGradient.locations = [0.0, 0.5, 1.0]
        overlayGradient.frame = view.bounds
        overlayGradient.zPosition = 1
        previewContainer.layer.addSublayer(overlayGradient)

        matteStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        matteStatusLabel.textColor = .white
        matteStatusLabel.textAlignment = .center
        matteStatusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        matteStatusLabel.numberOfLines = 0
        matteStatusLabel.text = "Preparing camera..."
        matteStatusLabel.layer.zPosition = 2
        view.addSubview(matteStatusLabel)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.configuration = .filled()
        captureButton.configuration?.baseBackgroundColor = .white
        captureButton.configuration?.baseForegroundColor = .black
        captureButton.configuration?.cornerStyle = .capsule
        captureButton.configuration?.title = "Capture"
        captureButton.configuration?.image = UIImage(systemName: "camera")
        captureButton.configuration?.imagePadding = 8
        captureButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        captureButton.layer.zPosition = 2
        view.addSubview(captureButton)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.layer.zPosition = 2
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.widthAnchor.constraint(equalToConstant: 34),
            cancelButton.heightAnchor.constraint(equalToConstant: 34),

            matteStatusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            matteStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 8),
            matteStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func requestPermissionAndConfigureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureSession()
                } else {
                    DispatchQueue.main.async {
                        self.matteStatusLabel.text = "Camera permission is required."
                        self.onError?("Camera permission is required for teeth matte capture.")
                    }
                }
            }
        default:
            matteStatusLabel.text = "Camera permission denied."
            onError?("Camera permission is denied. Enable it in Settings to use the playground camera.")
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.sessionConfigured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            do {
                guard
                    let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) ??
                        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.matteStatusLabel.text = "No front camera available."
                        self.onError?("No compatible front camera is available on this device.")
                    }
                    return
                }
                self.log("selected camera device: \(device.deviceType.rawValue), position: \(device.position.rawValue)")

                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    throw NSError(domain: "TeethMatteCapture", code: -10)
                }
                self.session.addInput(input)

                guard self.session.canAddOutput(self.photoOutput) else {
                    throw NSError(domain: "TeethMatteCapture", code: -11)
                }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                }
                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }
                self.photoOutput.enabledSemanticSegmentationMatteTypes = self.photoOutput.availableSemanticSegmentationMatteTypes
                self.log(
                    "output matte types available: \(self.matteTypesDescription(self.photoOutput.availableSemanticSegmentationMatteTypes)); enabled: \(self.matteTypesDescription(self.photoOutput.enabledSemanticSegmentationMatteTypes))"
                )

                self.teethMatteSupported = self.photoOutput.availableSemanticSegmentationMatteTypes.contains(.teeth)
                self.log("teeth matte supported during configure: \(self.teethMatteSupported)")
                self.sessionConfigured = true
                self.session.commitConfiguration()

                DispatchQueue.main.async {
                    self.matteStatusLabel.text = self.teethMatteSupported
                        ? "Teeth matte ready (AVSemanticSegmentationMatte)"
                        : "This camera cannot return teeth matte. You can still capture for preview."
                }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.matteStatusLabel.text = "Failed to configure camera."
                    self.onError?("Failed to configure camera capture.")
                }
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.sessionConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    @objc
    private func cancelTapped() {
        onCancel?()
    }

    @objc
    private func captureTapped() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.sessionConfigured else { return }

            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            if self.photoOutput.isDepthDataDeliveryEnabled {
                settings.isDepthDataDeliveryEnabled = true
            }
            if self.photoOutput.isPortraitEffectsMatteDeliveryEnabled {
                settings.isPortraitEffectsMatteDeliveryEnabled = true
            }
            self.log(
                "capture settings depthEnabled: \(settings.isDepthDataDeliveryEnabled), portraitMatteEnabled: \(settings.isPortraitEffectsMatteDeliveryEnabled)"
            )

            let matteSupportedNow = self.photoOutput.availableSemanticSegmentationMatteTypes.contains(.teeth)
            self.teethMatteSupported = matteSupportedNow
            self.log(
                "capture requested. matte available now: \(self.matteTypesDescription(self.photoOutput.availableSemanticSegmentationMatteTypes)); enabled on output: \(self.matteTypesDescription(self.photoOutput.enabledSemanticSegmentationMatteTypes))"
            )
            if matteSupportedNow {
                settings.enabledSemanticSegmentationMatteTypes = [.teeth]
                self.log("capture settings matte types: \(self.matteTypesDescription(settings.enabledSemanticSegmentationMatteTypes))")
            } else {
                self.log("capture settings matte types: none (.teeth unavailable)")
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            log("didFinishProcessingPhoto error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Photo capture failed.")
            }
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let rawImage = UIImage(data: data)
        else {
            log("didFinishProcessingPhoto invalid data or UIImage decode failed")
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Captured image data is invalid.")
            }
            return
        }
        log("didFinishProcessingPhoto image bytes: \(data.count), size: \(rawImage.size.width)x\(rawImage.size.height)")

        let normalizedPhoto = TeethPlaygroundImagePipeline.normalizedPhoto(rawImage)
        log("normalized photo size: \(normalizedPhoto.size.width)x\(normalizedPhoto.size.height)")
        let matteImage = extractTeethMask(from: photo)
        log("teeth matte image present: \(matteImage != nil)")
        let alignedMask = matteImage.map { TeethPlaygroundImagePipeline.normalizedMask($0, targetSize: normalizedPhoto.size) }
        if let alignedMask {
            log("aligned mask size: \(alignedMask.size.width)x\(alignedMask.size.height)")
        }

        let sample = TeethPlaygroundSample(
            photo: normalizedPhoto,
            teethMask: alignedMask,
            sourceDescription: alignedMask == nil
                ? "Playground camera (no teeth matte returned)"
                : "Playground camera (AVSemanticSegmentationMatte teeth)",
            hasSemanticTeethMatte: alignedMask != nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(sample)
        }
    }

    private func extractTeethMask(from photo: AVCapturePhoto) -> UIImage? {
        guard var matte = photo.semanticSegmentationMatte(for: .teeth) else {
            log("semanticSegmentationMatte(.teeth) returned nil")
            return nil
        }
        let pixelBuffer = matte.mattingImage
        log(
            "semanticSegmentationMatte(.teeth) available. pixelBuffer: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)), format: \(CVPixelBufferGetPixelFormatType(pixelBuffer))"
        )

        if
            let exifValue = photo.metadata[String(kCGImagePropertyOrientation)] as? NSNumber,
            let orientation = CGImagePropertyOrientation(rawValue: exifValue.uint32Value)
        {
            matte = matte.applyingExifOrientation(orientation)
            log("applied matte EXIF orientation: \(orientation.rawValue)")
        } else {
            log("no EXIF orientation found for matte")
        }

        let mask = TeethPlaygroundImagePipeline.maskImage(from: matte)
        log("mask conversion success: \(mask != nil)")
        return mask
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            log("didFinishCaptureFor error (uniqueID \(resolvedSettings.uniqueID)): \(error.localizedDescription)")
        } else {
            log("didFinishCaptureFor completed (uniqueID \(resolvedSettings.uniqueID))")
        }
    }

    private func log(_ message: String) {
        print("\(logPrefix) \(message)")
    }

    private func matteTypesDescription(_ types: [AVSemanticSegmentationMatte.MatteType]) -> String {
        if types.isEmpty {
            return "[]"
        }
        let labels = types.map { type in
            if type == .teeth { return "teeth" }
            if type == .skin { return "skin" }
            if type == .hair { return "hair" }
            return "unknown(\(type.rawValue))"
        }
        return "[\(labels.joined(separator: ", "))]"
    }
}

