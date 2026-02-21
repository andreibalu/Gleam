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
    private let flashAssistLabel = UILabel()
    private let flashAssistSwitch = UISwitch()
    private let flashAssistRow = UIStackView()
    private let flashOverlay = UIView()

    private var sessionConfigured = false
    private var teethMatteSupported = false
    private var frontCameraDevice: AVCaptureDevice?
    private var screenFlashEnabled = true
    private var lastLowLightDetected = false
    private var lastScreenFlashFired = false
    private var lastLowLightSnapshot: LowLightSnapshot?
    private var captureSequence = 0
    private var lastCaptureID = 0
    private var flashInFlight = false
    private var storedScreenBrightness: CGFloat?
    private let verboseCameraLogsEnabled = false
    private let logPrefix = "[TeethPlaygroundCamera]"
    private let captureResultLogPrefix = "[TeethPlaygroundCaptureResult]"
    private let lowLightOffsetHardThreshold: Float = -0.8
    private let lowLightIsoRatioHardThreshold: Float = 20.0
    private let lowLightIsoRatioSoftThreshold: Float = 14.0
    private let lowLightOffsetSoftThreshold: Float = -0.2

    private struct MaskSanity {
        let hardCoverage: Double
        let weightedCoverage: Double
    }

    private struct LowLightSnapshot {
        let exposureOffset: Float
        let iso: Float
        let minISO: Float
        let isoRatio: Float
        let detected: Bool
        let trigger: String
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        observeLifecycleEvents()
        requestPermissionAndConfigureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
        restoreScreenBrightnessIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        flashAssistLabel.translatesAutoresizingMaskIntoConstraints = false
        flashAssistLabel.textColor = .white
        flashAssistLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        flashAssistLabel.text = "Lighting assist"

        flashAssistSwitch.translatesAutoresizingMaskIntoConstraints = false
        flashAssistSwitch.isOn = screenFlashEnabled
        flashAssistSwitch.addTarget(self, action: #selector(flashAssistChanged), for: .valueChanged)

        flashAssistRow.translatesAutoresizingMaskIntoConstraints = false
        flashAssistRow.axis = .horizontal
        flashAssistRow.alignment = .center
        flashAssistRow.spacing = 8
        flashAssistRow.addArrangedSubview(flashAssistLabel)
        flashAssistRow.addArrangedSubview(flashAssistSwitch)
        flashAssistRow.layer.zPosition = 2
        view.addSubview(flashAssistRow)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.layer.zPosition = 2
        view.addSubview(cancelButton)

        flashOverlay.translatesAutoresizingMaskIntoConstraints = false
        flashOverlay.backgroundColor = .white
        flashOverlay.alpha = 0
        flashOverlay.isUserInteractionEnabled = false
        flashOverlay.layer.zPosition = 1.5
        previewContainer.addSubview(flashOverlay)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.widthAnchor.constraint(equalToConstant: 34),
            cancelButton.heightAnchor.constraint(equalToConstant: 34),

            matteStatusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            matteStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 8),
            matteStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            flashAssistRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flashAssistRow.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -12),

            flashOverlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            flashOverlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            flashOverlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            flashOverlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
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

    private func observeLifecycleEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc
    private func handleAppWillResignActive() {
        restoreScreenBrightnessIfNeeded()
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
                self.frontCameraDevice = device

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
                    self.updateFlashAssistStatusLabel(lowLight: false)
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
        restoreScreenBrightnessIfNeeded()
        onCancel?()
    }

    @objc
    private func flashAssistChanged() {
        screenFlashEnabled = flashAssistSwitch.isOn
        updateFlashAssistStatusLabel(lowLight: lastLowLightDetected)
    }

    @objc
    private func captureTapped() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.sessionConfigured else { return }
            let lowLightSnapshot = self.detectLowLightSnapshot()
            let lowLightDetected = lowLightSnapshot?.detected ?? false
            self.lastLowLightDetected = lowLightDetected
            self.lastLowLightSnapshot = lowLightSnapshot
            let shouldFlash = self.shouldFireScreenFlash(lowLightDetected: lowLightDetected)
            self.lastScreenFlashFired = shouldFlash
            self.captureSequence += 1
            self.lastCaptureID = self.captureSequence

            DispatchQueue.main.async {
                self.updateFlashAssistStatusLabel(lowLight: lowLightDetected)
            }
            if shouldFlash {
                self.triggerScreenFlash()
            }

            self.logCaptureRequest(
                captureID: self.lastCaptureID,
                lowLightSnapshot: lowLightSnapshot,
                lowLightDetected: lowLightDetected,
                shouldFlash: shouldFlash
            )

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
            logError("didFinishProcessingPhoto error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Photo capture failed.")
            }
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let rawImage = UIImage(data: data)
        else {
            logError("didFinishProcessingPhoto invalid data or UIImage decode failed")
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
        let maskSanity = alignedMask.flatMap(maskSanityMetrics)
        if let alignedMask {
            log("aligned mask size: \(alignedMask.size.width)x\(alignedMask.size.height)")
        }
        if let maskSanity {
            log(
                "mask sanity hardCoverage: \(String(format: "%.4f", maskSanity.hardCoverage)), weightedCoverage: \(String(format: "%.4f", maskSanity.weightedCoverage))"
            )
        }

        let weakMatte = (maskSanity?.hardCoverage ?? 0) < 0.0025 || (maskSanity?.weightedCoverage ?? 0) < 0.003
        let sourceDescription: String
        if alignedMask == nil {
            sourceDescription = "Playground camera (no teeth matte returned)"
        } else if weakMatte {
            sourceDescription = "Playground camera (teeth matte detected but weak coverage)"
        } else {
            sourceDescription = "Playground camera (AVSemanticSegmentationMatte teeth)"
        }

        let sample = TeethPlaygroundSample(
            photo: normalizedPhoto,
            teethMask: alignedMask,
            sourceDescription: sourceDescription,
                hasSemanticTeethMatte: alignedMask != nil,
                captureContext: TeethPlaygroundCaptureContext(
                    source: .camera,
                    lowLightDetected: lastLowLightDetected,
                    lightingAssistEnabled: screenFlashEnabled,
                    lightingAssistUsed: lastScreenFlashFired,
                    screenFlashFired: lastScreenFlashFired
                )
        )

        logCaptureResult(
            captureID: lastCaptureID,
            photoSize: normalizedPhoto.size,
            hasTeethMatte: alignedMask != nil,
            weakMatte: weakMatte,
            maskSanity: maskSanity,
            captureContext: sample.captureContext,
            lowLightSnapshot: lastLowLightSnapshot
        )

        DispatchQueue.main.async { [weak self] in
            if weakMatte {
                self?.matteStatusLabel.text = "Teeth matte returned, but coverage is weak. Retake with brighter light."
            }
            self?.onCapture?(sample)
            self?.restoreScreenBrightnessIfNeeded()
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
            logError("didFinishCaptureFor error (uniqueID \(resolvedSettings.uniqueID)): \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        guard verboseCameraLogsEnabled else { return }
        print("\(logPrefix) \(message)")
    }

    private func logError(_ message: String) {
        print("\(logPrefix) [error] \(message)")
    }

    private func logCaptureRequest(
        captureID: Int,
        lowLightSnapshot: LowLightSnapshot?,
        lowLightDetected: Bool,
        shouldFlash: Bool
    ) {
        print(
            "\(captureResultLogPrefix) phase=request shot=\(captureID) lowLight=\(boolText(lowLightDetected)) lowLightTrigger=\(lowLightSnapshot?.trigger ?? "n/a") exposureOffset=\(format(lowLightSnapshot?.exposureOffset)) isoRatio=\(format(lowLightSnapshot?.isoRatio)) iso=\(format(lowLightSnapshot?.iso)) minISO=\(format(lowLightSnapshot?.minISO)) assistEnabled=\(boolText(screenFlashEnabled)) assistWillFire=\(boolText(shouldFlash))"
        )
    }

    private func logCaptureResult(
        captureID: Int,
        photoSize: CGSize,
        hasTeethMatte: Bool,
        weakMatte: Bool,
        maskSanity: MaskSanity?,
        captureContext: TeethPlaygroundCaptureContext,
        lowLightSnapshot: LowLightSnapshot?
    ) {
        let hardCoverage = format(maskSanity?.hardCoverage)
        let weightedCoverage = format(maskSanity?.weightedCoverage)
        let lowLightSource = lowLightSnapshot == nil ? "unknown" : "camera"
        print(
            "\(captureResultLogPrefix) phase=result shot=\(captureID) lowLight=\(boolText(captureContext.lowLightDetected)) lowLightSource=\(lowLightSource) lowLightTrigger=\(lowLightSnapshot?.trigger ?? "n/a") exposureOffset=\(format(lowLightSnapshot?.exposureOffset)) isoRatio=\(format(lowLightSnapshot?.isoRatio)) assistEnabled=\(boolText(captureContext.lightingAssistEnabled)) assistFired=\(boolText(captureContext.lightingAssistUsed)) matte=\(boolText(hasTeethMatte)) weakMatte=\(boolText(weakMatte)) hardCoverage=\(hardCoverage) weightedCoverage=\(weightedCoverage) photo=\(Int(photoSize.width))x\(Int(photoSize.height))"
        )
    }

    private func detectLowLightSnapshot() -> LowLightSnapshot? {
        guard let device = frontCameraDevice else { return nil }
        do {
            try device.lockForConfiguration()
            let offset = device.exposureTargetOffset
            let iso = device.iso
            let minISO = max(device.activeFormat.minISO, 1)
            let isoRatio = iso / minISO
            device.unlockForConfiguration()

            let hardOffsetLow = offset < lowLightOffsetHardThreshold
            let hardIsoLow = isoRatio >= lowLightIsoRatioHardThreshold
            let softIsoWithOffsetLow = isoRatio >= lowLightIsoRatioSoftThreshold && offset <= lowLightOffsetSoftThreshold
            let detected = hardOffsetLow || hardIsoLow || softIsoWithOffsetLow
            let trigger: String
            if hardOffsetLow {
                trigger = "offset_hard"
            } else if hardIsoLow {
                trigger = "iso_hard"
            } else if softIsoWithOffsetLow {
                trigger = "iso_soft_offset"
            } else {
                trigger = "none"
            }

            return LowLightSnapshot(
                exposureOffset: offset,
                iso: iso,
                minISO: minISO,
                isoRatio: isoRatio,
                detected: detected,
                trigger: trigger
            )
        } catch {
            logError("low-light check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func boolText(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private func format(_ value: Float?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.3f", value)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.4f", value)
    }

    private func shouldFireScreenFlash(lowLightDetected: Bool) -> Bool {
        guard screenFlashEnabled else { return false }
        guard !UIAccessibility.isReduceMotionEnabled else { return false }
        return lowLightDetected
    }

    private func triggerScreenFlash() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.flashInFlight else { return }
            self.flashInFlight = true

            let original = UIScreen.main.brightness
            self.storedScreenBrightness = original
            UIScreen.main.brightness = min(1.0, max(original, 0.85))

            UIView.animate(withDuration: 0.05, delay: 0, options: [.curveEaseOut]) {
                self.flashOverlay.alpha = 0.96
            } completion: { _ in
                UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseIn]) {
                    self.flashOverlay.alpha = 0
                } completion: { _ in
                    self.flashInFlight = false
                }
            }
        }
    }

    private func restoreScreenBrightnessIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let stored = self.storedScreenBrightness else { return }
            self.storedScreenBrightness = nil
            UIScreen.main.brightness = stored
        }
    }

    private func updateFlashAssistStatusLabel(lowLight: Bool) {
        let status: String
        if !screenFlashEnabled {
            status = "Lighting assist off"
        } else if lowLight {
            status = "Lighting assist auto-ready (low light)"
        } else {
            status = "Lighting assist on"
        }
        flashAssistLabel.text = status
    }

    private func maskSanityMetrics(_ image: UIImage) -> MaskSanity? {
        guard let raster = rasterizedMaskRGBA(from: image) else { return nil }
        let totalPixels = raster.width * raster.height
        guard totalPixels > 0 else { return nil }

        var hardCount = 0
        var weightSum = 0.0
        for pixel in 0..<totalPixels {
            let offset = pixel * 4
            let matte = Double(raster.bytes[offset]) / 255.0
            if matte > 0.35 {
                hardCount += 1
            }
            if matte > 0.12 {
                weightSum += matte
            }
        }

        return MaskSanity(
            hardCoverage: Double(hardCount) / Double(totalPixels),
            weightedCoverage: weightSum / Double(totalPixels)
        )
    }

    private func rasterizedMaskRGBA(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width, height)
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

