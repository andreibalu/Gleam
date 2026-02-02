import SwiftUI
import PhotosUI
import UIKit
import Vision

struct ScanView: View {
    @Environment(\.scanRepository) private var scanRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isAnalyzing = false
    @State private var showCamera = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    private let stainTags = StainTag.defaults
    @State private var selectedTagIDs: Set<String> = []

    var onFinished: (ScanResult) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                AppBackground()
                
                VStack(spacing: 0) {
                    // Main content area
                    ZStack {
                        if let data = selectedImageData, let uiImage = UIImage(data: data) {
                            SelectedPhotoView(image: uiImage)
                        } else {
                            ScanPlaceholderView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isAnalyzing ? 0 : 1)
                    .allowsHitTesting(!isAnalyzing)

                    if selectedImageData != nil {
                        StainTagSelector(
                            tags: stainTags,
                            selectedTagIDs: $selectedTagIDs
                        )
                        .padding(.horizontal, AppSpacing.l)
                        .padding(.top, AppSpacing.m)
                        .opacity(isAnalyzing ? 0 : 1)
                        .allowsHitTesting(!isAnalyzing)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isAnalyzing)
                // Floating Action Buttons - invisible background, pure focus on actions
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: AppSpacing.m) {
                        if isAnalyzing {
                            // Hide actions during analysis
                            EmptyView()
                        } else if selectedImageData == nil {
                            // Initial state: Take photo or choose from library
                            VStack(spacing: AppSpacing.s) {
                                Button {
                                    showCamera = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "camera.fill")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("Take Photo")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                }
                                .buttonStyle(FloatingPrimaryButtonStyle())
                                .accessibilityIdentifier("scan_take_photo_button")
                                
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text("Choose from Library")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                }
                                .buttonStyle(FloatingSecondaryButtonStyle())
                                .onChange(of: photoItem) { _, newItem in
                                    Task { await loadImage(from: newItem) }
                                }
                            }
                        } else {
                            // Image selected state
                            VStack(spacing: AppSpacing.m) {
                                if !isAnalyzing {
                                    // Compact action buttons side by side
                                    HStack(spacing: AppSpacing.m) {
                                        Button {
                                            showCamera = true
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: "camera.fill")
                                                    .font(.title2)
                                                    .fontWeight(.medium)
                                                Text("Retake")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                        }
                                        .buttonStyle(FloatingIconButtonStyle())
                                        .accessibilityIdentifier("scan_take_new_photo_button")
                                        
                                        PhotosPicker(selection: $photoItem, matching: .images) {
                                            VStack(spacing: 6) {
                                                Image(systemName: "photo.on.rectangle")
                                                    .font(.title2)
                                                    .fontWeight(.medium)
                                                Text("Choose")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                        }
                                        .buttonStyle(FloatingIconButtonStyle())
                                        .onChange(of: photoItem) { _, newItem in
                                            Task { await loadImage(from: newItem) }
                                        }
                                    }
                                }
                                
                                // Analyze button - hero action
                                Button {
                                    Task { await analyze() }
                                } label: {
                                    HStack(spacing: 12) {
                                        if isAnalyzing {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "sparkles")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                        }
                                        Text(isAnalyzing ? "Analyzing..." : "Analyze Photo")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                }
                                .buttonStyle(FloatingPrimaryButtonStyle())
                                .disabled(isAnalyzing)
                                .opacity(isAnalyzing ? 0.7 : 1.0)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.top, selectedImageData == nil ? AppSpacing.xl : AppSpacing.m)
                    .padding(.bottom, AppSpacing.l)
                }

                if isAnalyzing {
                    AnalysisOverlay(imageData: selectedImageData)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .onAppear {
            if let capturedData = scanSession.capturedImageData {
                selectedImageData = capturedData
                selectedTagIDs.removeAll()
                scanSession.capturedImageData = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { data in
                if let data = data {
                    selectedImageData = data
                    selectedTagIDs.removeAll()
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: scanSession.shouldOpenCamera) { _, shouldOpen in
            if shouldOpen {
                showCamera = true
                scanSession.shouldOpenCamera = false
            }
        }
        .alert("Photo Validation", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = compressImageDataIfNeeded(data)
                selectedTagIDs.removeAll()
            }
        } catch { }
    }

    @MainActor
    private func analyze() async {
        guard let data = selectedImageData else { return }
        
        // Validate that the image contains a face before proceeding
        let faceValidation = await validateImageContainsFace(imageData: data)
        switch faceValidation {
        case .noFace:
            errorMessage = "No face detected in this photo. Please take a photo that clearly shows a person's face."
            showErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        case .noSmile:
            errorMessage = "Please smile to show your teeth! We need to see your teeth clearly for the analysis."
            showErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        case .valid:
            break
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isAnalyzing = true
        defer {
            isAnalyzing = false
            // Clear the image after analysis so Scan tab shows placeholder again
            selectedImageData = nil
            selectedTagIDs.removeAll()
        }

        let selectedTags = stainTags.filter { selectedTagIDs.contains($0.id) }
        let tagKeywords = selectedTags.map { $0.promptKeyword }
        let previousTakeaways = historyStore.items
            .compactMap { $0.result.personalTakeaway.isEmpty ? nil : $0.result.personalTakeaway }
            .prefix(5)
        let recentTagHistory = historyStore.items
            .prefix(5)
            .map { $0.contextTags }

        do {
            // Crop image to teeth region for API call to save tokens
            // Keep original image for history display
            let imageToAnalyze = await cropImageToTeethRegion(imageData: data) ?? data
            
            let outcome = try await scanRepository.analyze(
                imageData: imageToAnalyze,
                tags: tagKeywords,
                previousTakeaways: Array(previousTakeaways),
                recentTagHistory: Array(recentTagHistory)
            )
            // Save result with original image data and tag context
            historyStore.append(
                outcome: outcome,
                imageData: data,
                fallbackContextTags: selectedTags.map { $0.id }
            )
            onFinished(outcome.result)
        } catch { }
    }
    
    /// Validation result for image face detection
    private enum FaceValidationResult {
        case valid
        case noFace
        case noSmile
    }
    
    /// Validates that the image contains a human face and that the person is smiling/showing teeth
    private func validateImageContainsFace(imageData: Data) async -> FaceValidationResult {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return .noFace
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { req, error in
                if let error = error {
                    continuation.resume(returning: .noFace)
                    return
                }
                
                // Check if any face is detected
                guard let observations = req.results as? [VNFaceObservation],
                      let firstFace = observations.first else {
                    continuation.resume(returning: .noFace)
                    return
                }
                
                // Check if we can detect mouth landmarks
                guard let landmarks = firstFace.landmarks,
                      let outerLips = landmarks.outerLips else {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                // Check if inner lips are detected (indicates mouth is open, showing teeth)
                guard let innerLips = landmarks.innerLips else {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                // Calculate mouth opening to verify teeth are visible
                let outerPoints = outerLips.normalizedPoints
                let innerPoints = innerLips.normalizedPoints
                
                guard !outerPoints.isEmpty && !innerPoints.isEmpty else {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                // Find the vertical gap between top and bottom of inner lips
                // In Vision coordinates, y=0 is at the bottom, so higher y values are higher up
                let innerTopY = innerPoints.map { CGFloat($0.y) }.max() ?? 0
                let innerBottomY = innerPoints.map { CGFloat($0.y) }.min() ?? 0
                
                // Calculate mouth opening height (normalized to face size)
                let mouthOpening = innerTopY - innerBottomY
                
                // If mouth opening is too small, teeth are likely not visible
                // Threshold: mouth should be open at least 1.5% of face height
                let minMouthOpening: CGFloat = 0.015
                if mouthOpening < minMouthOpening {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                // Additional check: verify mouth shape indicates a smile
                // In a smile, the mouth opening should be wider and the corners should be raised
                // Get left and right corners of outer lips
                let outerXCoords = outerPoints.map { CGFloat($0.x) }
                guard let leftCornerX = outerXCoords.min(),
                      let rightCornerX = outerXCoords.max() else {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                // Calculate mouth width (normalized)
                let mouthWidth = rightCornerX - leftCornerX
                
                // Find Y coordinates at the corners
                let leftCornerPoints = outerPoints.filter { abs(CGFloat($0.x) - leftCornerX) < 0.05 }
                let rightCornerPoints = outerPoints.filter { abs(CGFloat($0.x) - rightCornerX) < 0.05 }
                
                guard !leftCornerPoints.isEmpty && !rightCornerPoints.isEmpty else {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                let leftCornerY = leftCornerPoints.map { CGFloat($0.y) }.reduce(0, +) / CGFloat(leftCornerPoints.count)
                let rightCornerY = rightCornerPoints.map { CGFloat($0.y) }.reduce(0, +) / CGFloat(rightCornerPoints.count)
                
                // Find the lowest point of the outer lips (typically the center bottom)
                let lowestY = outerPoints.map { CGFloat($0.y) }.min() ?? 0
                
                // In Vision coordinates (bottom-left origin), higher y = higher up on face
                // For a smile, corners should be higher (raised) compared to the lowest point
                // We check if corners are significantly above the lowest point
                let cornerRaiseThreshold: CGFloat = 0.02 // 2% of face height
                let leftCornerRaised = leftCornerY > lowestY + cornerRaiseThreshold
                let rightCornerRaised = rightCornerY > lowestY + cornerRaiseThreshold
                
                // At least one corner should be raised, and mouth should be reasonably wide
                let minMouthWidth: CGFloat = 0.15 // At least 15% of face width
                if (!leftCornerRaised && !rightCornerRaised) || mouthWidth < minMouthWidth {
                    continuation.resume(returning: .noSmile)
                    return
                }
                
                continuation.resume(returning: .valid)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: .noFace)
                }
            }
        }
    }
    
    /// Crops the image to the detected teeth/mouth region using Vision framework
    /// Returns nil if detection fails, allowing fallback to original image
    private func cropImageToTeethRegion(imageData: Data) async -> Data? {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { req, _ in
                guard
                    let obs = (req.results as? [VNFaceObservation])?.first,
                    let lips = obs.landmarks?.outerLips ?? obs.landmarks?.innerLips
                else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert lip points (normalized within face) to normalized in full image (origin bottom-left in Vision)
                let face = obs.boundingBox
                let points = lips.normalizedPoints.map { p -> CGPoint in
                    let xInFace = CGFloat(p.x)
                    let yInFace = CGFloat(p.y)
                    let x = face.origin.x + xInFace * face.size.width
                    let yBL = face.origin.y + yInFace * face.size.height
                    // Vision uses bottom-left origin, convert to top-left for image cropping
                    let y = 1.0 - yBL
                    return CGPoint(x: x, y: y)
                }
                
                guard let first = points.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Find bounding box of mouth region
                var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
                for pt in points {
                    minX = min(minX, pt.x)
                    maxX = max(maxX, pt.x)
                    minY = min(minY, pt.y)
                    maxY = max(maxY, pt.y)
                }
                
                // Add padding around the mouth region
                let pad: CGFloat = 0.15 // 15% padding on all sides
                let width = maxX - minX
                let height = maxY - minY
                let paddedMinX = max(0, minX - width * pad)
                let paddedMinY = max(0, minY - height * pad)
                let paddedMaxX = min(1, maxX + width * pad)
                let paddedMaxY = min(1, maxY + height * pad)
                
                // Convert normalized coordinates (top-left origin) to pixel coordinates
                // CGImage cropping uses top-left origin (standard CoreGraphics coordinate system)
                let imageWidth = CGFloat(cgImage.width)
                let imageHeight = CGFloat(cgImage.height)
                let cropRect = CGRect(
                    x: paddedMinX * imageWidth,
                    y: paddedMinY * imageHeight, // Already in top-left origin
                    width: (paddedMaxX - paddedMinX) * imageWidth,
                    height: (paddedMaxY - paddedMinY) * imageHeight
                )
                
                // Crop the image
                guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
                
                // Compress the cropped image
                let compressedData = croppedImage.jpegData(compressionQuality: 0.8)
                continuation.resume(returning: compressedData)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func compressImageDataIfNeeded(_ data: Data) -> Data? {
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

// MARK: - Scan Placeholder View
private struct ScanPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var backgroundGradient: LinearGradient {
        let lightColors = [
            Color(red: 0.93, green: 0.95, blue: 0.98),
            Color(red: 0.96, green: 0.94, blue: 0.98)
        ]
        let darkColors = [
            Color(red: 0.08, green: 0.09, blue: 0.14),
            Color(red: 0.11, green: 0.09, blue: 0.18)
        ]
        return LinearGradient(
            colors: isDarkMode ? darkColors : lightColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var circleFill: Color {
        isDarkMode ? Color(.tertiarySystemBackground).opacity(0.95) : Color.white.opacity(0.95)
    }

    private var cardFill: Color {
        isDarkMode ? Color(.secondarySystemBackground).opacity(0.95) : Color.white.opacity(0.85)
    }

    private var cardShadow: Color {
        isDarkMode ? Color.black.opacity(0.4) : Color.black.opacity(0.05)
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            // Circle scales with available height to avoid pushing buttons off screen
            let circleSize = min(w * 0.72, h * 0.40)
            let glowSize = circleSize * 1.13
            
            ZStack {
                // Subtle gradient background
                backgroundGradient
                
                VStack(spacing: AppSpacing.l) {
                    // Elegant circular image container
                    ZStack {
                        // Outer glow effect
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.15),
                                        Color.purple.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: glowSize, height: glowSize)
                            .blur(radius: 18)
                        
                        // Main image circle
                        Circle()
                            .fill(circleFill)
                            .frame(width: circleSize, height: circleSize)
                            .shadow(color: Color.blue.opacity(0.1), radius: 16, x: 0, y: 8)
                        
                        Image("ScanPlaceholder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: circleSize * 0.93, height: circleSize * 0.93)
                            .clipShape(Circle())
                    }
                    
                    // Instructions card
                    VStack(spacing: AppSpacing.m) {
                        Text("How to Take Your Photo")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        VStack(alignment: .leading, spacing: AppSpacing.m) {
                            InstructionRow(number: 1, text: "Position your phone at eye level")
                            InstructionRow(number: 2, text: "Smile naturally 🦷")
                            InstructionRow(number: 3, text: "Ensure good lighting")
                            InstructionRow(number: 4, text: "Keep your head straight")
                        }
                    }
                    .padding(.vertical, AppSpacing.m)
                    .padding(.horizontal, AppSpacing.l)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                            .fill(cardFill)
                            .shadow(color: cardShadow, radius: 12, x: 0, y: 4)
                    )
                    .padding(.horizontal, AppSpacing.l)
                    .layoutPriority(1)
                    
                    Spacer(minLength: 0)
                }
                .padding(.top, AppSpacing.l)
                .padding(.bottom, AppSpacing.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Selected Photo View
private struct SelectedPhotoView: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: UIImage
    
    private var accentBackground: LinearGradient {
        let lightColors = [
            Color.blue.opacity(0.07),
            Color.purple.opacity(0.05)
        ]
        let darkColors = [
            Color.blue.opacity(0.18),
            Color.purple.opacity(0.14)
        ]
        return LinearGradient(
            colors: colorScheme == .dark ? darkColors : lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let availableSize = proxy.size
            let aspect: CGFloat = 3.0 / 4.0
            let maxWidth = min(availableSize.width * 0.88, 420)
            let maxHeight = min(availableSize.height * 0.75, 540)
            
            let finalDimensions: (width: CGFloat, height: CGFloat) = {
                var width = maxWidth
                var height = width / aspect
                
                if height > maxHeight {
                    height = maxHeight
                    width = height * aspect
                }
                
                return (width, height)
            }()
            
            let finalWidth = finalDimensions.width
            let finalHeight = finalDimensions.height
            
            VStack(spacing: AppSpacing.l) {
                Spacer(minLength: AppSpacing.m)
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: finalWidth, height: finalHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 12)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    )
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.large + 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(0.65)
                            .blur(radius: 0)
                    )
                    .padding(AppSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.large + 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                    )
                
                Spacer(minLength: AppSpacing.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                accentBackground
            )
            .padding(.horizontal, AppSpacing.l)
        }
    }
}

// MARK: - Instruction Row
private struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: AppSpacing.m) {
            // Gradient circle with number
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Text("\(number)")
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Analysis Overlay
private struct AnalysisOverlay: View {
    private let image: UIImage?
    @State private var haloPulse = false
    @State private var ringRotation = false
    @State private var mouthFocus: MouthFocus? = nil
    
    init(imageData: Data?) {
        if let data = imageData {
            self.image = UIImage(data: data)
        } else {
            self.image = nil
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            // Base size used for image; ring scales independently to appear larger
            let baseSize = min(proxy.size.width, proxy.size.height) * 0.58
            let imageSize = baseSize * 0.82
            let ringDiameter = imageSize * 1.6
            
        ZStack {
                // Keep underlying Scan screen visible; add tasteful edge glow that fades toward center
                EdgeVignetteOverlay()
                .ignoresSafeArea()
            
                VStack(spacing: AppSpacing.xl) {
                ZStack {
                    Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.04)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: baseSize * 0.8
                                )
                            )
                            .frame(width: baseSize * 1.25, height: baseSize * 1.25)
                            .scaleEffect(haloPulse ? 1.03 : 0.97)
                            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: haloPulse)
                        
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.6)
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 2.5)
                            )
                            .frame(width: baseSize * 1.1, height: baseSize * 1.1)
                            .blur(radius: 10)
                            .opacity(0.7)
                        
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color(red: 0.43, green: 0.63, blue: 1.0),
                                        Color(red: 0.71, green: 0.46, blue: 1.0),
                                        Color(red: 0.43, green: 0.63, blue: 1.0)
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: ringDiameter, height: ringDiameter)
                            .rotationEffect(.degrees(ringRotation ? 360 : 0))
                            .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: ringRotation)
                        
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imageSize, height: imageSize)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                                .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .blendMode(.softLight)
                                )
                                .overlay {
                                    if let focus = mouthFocus {
                                        MouthFocusIndicator(imageSize: imageSize, focus: focus, cornerRadius: AppRadius.large)
                                            .transition(.opacity)
                }
                                }
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: baseSize * 0.32, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: AppSpacing.s) {
                Text("Analyzing Your Smile")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.92))
                        Text("We’re polishing the details to craft your personalized insights.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    
                    ShimmeringProgressCapsule()
                        .padding(.horizontal, AppSpacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, AppSpacing.xl)
            }
        }
        .transition(.opacity)
        .onAppear {
            haloPulse = true
            ringRotation = true
            if let img = image {
                Task { mouthFocus = await detectMouthFocus(in: img) }
            }
        }
    }
}

// MARK: - Elegant edge glow that preserves center content
private struct EdgeVignetteOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            ZStack {
                // Radial fade from transparent center to themed hues at edges
                RadialGradient(
                    colors: [
                        .clear,
                        Color.blue.opacity(0.10),
                        Color.purple.opacity(0.16),
                        Color.black.opacity(0.18)
                    ],
                    center: .center,
                    startRadius: maxDim * 0.15,
                    endRadius: maxDim * 0.65
                )
                .blendMode(.plusLighter)
                
                // Subtle corner tints
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.10),
                        .clear,
                        Color.blue.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.6)
            }
        }
    }
}

// MARK: - Mouth/Teeth focus vignette
// MARK: - Mouth focus indicator types and view
private struct MouthFocus {
    let rect: CGRect // normalized to 0...1, origin top-left
}

private struct MouthFocusIndicator: View {
    let imageSize: CGFloat
    let focus: MouthFocus
    let cornerRadius: CGFloat
    
    var body: some View {
        Canvas { context, _ in
            let outer = CGRect(x: 0, y: 0, width: imageSize, height: imageSize)
            let focusRect = CGRect(
                x: focus.rect.origin.x * imageSize,
                y: focus.rect.origin.y * imageSize,
                width: focus.rect.size.width * imageSize,
                height: focus.rect.size.height * imageSize
            )
            .insetBy(dx: -6, dy: -6)
            
            var path = Path(roundedRect: outer, cornerRadius: cornerRadius)
            path.addPath(Path(roundedRect: focusRect, cornerRadius: 14))
            context.fill(path, with: .color(Color.black.opacity(0.35)), style: FillStyle(eoFill: true))
            
            context.stroke(
                Path(roundedRect: focusRect, cornerRadius: 14),
                with: .color(.white),
                lineWidth: 2.5
            )
        }
        .frame(width: imageSize, height: imageSize)
        .allowsHitTesting(false)
    }
}

// MARK: - Vision utility
private extension AnalysisOverlay {
    func detectMouthFocus(in image: UIImage) async -> MouthFocus? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { req, _ in
                guard
                    let obs = (req.results as? [VNFaceObservation])?.first,
                    let lips = obs.landmarks?.outerLips ?? obs.landmarks?.innerLips
                else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert lip points (normalized within face) to normalized in full image (origin top-left)
                let face = obs.boundingBox // origin is bottom-left in Vision
                let points = lips.normalizedPoints.map { p -> CGPoint in
                    // p is in face box coordinates (origin bottom-left). Convert to image coords.
                    let xInFace = CGFloat(p.x)
                    let yInFace = CGFloat(p.y)
                    let x = face.origin.x + xInFace * face.size.width
                    let yBL = face.origin.y + yInFace * face.size.height
                    // flip y to top-left origin
                    let y = 1.0 - yBL
                    return CGPoint(x: x, y: y)
                }
                
                guard let first = points.first else {
                    continuation.resume(returning: nil)
                    return
                }
                var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
                for pt in points {
                    minX = min(minX, pt.x)
                    maxX = max(maxX, pt.x)
                    minY = min(minY, pt.y)
                    maxY = max(maxY, pt.y)
                }
                let pad: CGFloat = 0.03
                let rect = CGRect(
                    x: max(0, minX - pad),
                    y: max(0, minY - pad * 0.6),
                    width: min(1, maxX + pad) - max(0, minX - pad),
                    height: min(1, maxY + pad * 1.2) - max(0, minY - pad * 0.6)
                )
                continuation.resume(returning: MouthFocus(rect: rect))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
private struct ShimmeringProgressCapsule: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmer = false
    
    private var capsuleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.35)
    }

    private var capsuleStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12)
    }

    private var shimmerColors: [Color] {
        colorScheme == .dark
            ? [Color.white.opacity(0), Color.white.opacity(0.7), Color.white.opacity(0)]
            : [Color.white.opacity(0), Color.white.opacity(0.9), Color.white.opacity(0)]
    }

    private var capsuleTextColor: Color {
        Color.primary.opacity(0.9)
    }

    private var capsuleShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.15)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(capsuleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(capsuleStroke, lineWidth: 1)
                )
                .frame(height: 56)
                .overlay(
                    GeometryReader { geo in
                        let width = geo.size.width
                        LinearGradient(
                            gradient: Gradient(colors: [
                                shimmerColors[0],
                                shimmerColors[1],
                                shimmerColors[2]
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.45)
                        .offset(x: shimmer ? width : -width)
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: shimmer)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                )
                .overlay(
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(capsuleTextColor)
                            .shadow(color: capsuleShadow.opacity(0.25), radius: 2, x: 0, y: 0)
                        Text("Analyzing…")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(capsuleTextColor)
            }
                )
                .compositingGroup()
                .shadow(color: capsuleShadow, radius: 16, x: 0, y: 10)
        }
        .onAppear {
            shimmer = true
        }
    }
}

// MARK: - Stain Tag Selector
private struct StainTagSelector: View {
    let tags: [StainTag]
    @Binding var selectedTagIDs: Set<String>
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: AppSpacing.s)]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("Anything staining lately?")
                .font(.headline)
            Text("Pick the habits that might be tinting your teeth. We'll factor them into the analysis.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
                ForEach(tags) { tag in
                    StainTagChip(
                        tag: tag,
                        isSelected: selectedTagIDs.contains(tag.id),
                        onToggle: { toggle(tag) }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    private func toggle(_ tag: StainTag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }
}

private struct StainTagChip: View {
    let tag: StainTag
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                Text(tag.title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? Color.blue : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.blue : Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}


