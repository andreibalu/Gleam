import SwiftUI
import PhotosUI
import UIKit

struct ScanView: View {
    @Environment(\.scanRepository) private var scanRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isAnalyzing = false
    private let stainTags = StainTag.defaults
    @State private var selectedTagIDs: Set<String> = []

    var onFinished: (ScanResult) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.98, green: 0.95, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Main content area
                    ZStack {
                        if let data = selectedImageData, let uiImage = UIImage(data: data) {
                            SelectedPhotoView(image: uiImage)
                                .overlay {
                                    if isAnalyzing {
                                        AnalysisOverlay()
                                    }
                                }
                        } else {
                            ScanPlaceholderView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if selectedImageData != nil {
                        StainTagSelector(
                            tags: stainTags,
                            selectedTagIDs: $selectedTagIDs
                        )
                        .padding(.horizontal, AppSpacing.l)
                        .padding(.top, AppSpacing.m)
                    }
                }
                // Floating Action Buttons - invisible background, pure focus on actions
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: AppSpacing.m) {
                        if selectedImageData == nil {
                            // Initial state: Take photo or choose from library
                            VStack(spacing: AppSpacing.s) {
                                Button {
                                    scanSession.shouldOpenCamera = true
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
                                            scanSession.shouldOpenCamera = true
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
            }
        }
        .onAppear {
            if let capturedData = scanSession.capturedImageData {
                selectedImageData = capturedData
                selectedTagIDs.removeAll()
                scanSession.capturedImageData = nil
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

    private func analyze() async {
        guard let data = selectedImageData else { return }
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

        do {
            let result = try await scanRepository.analyze(
                imageData: data,
                tags: tagKeywords,
                previousTakeaways: Array(previousTakeaways)
            )
            // Save result with image data and tag context
            historyStore.append(
                result,
                imageData: data,
                contextTags: selectedTags.map { $0.id }
            )
            onFinished(result)
        } catch { }
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
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            // Circle scales with available height to avoid pushing buttons off screen
            let circleSize = min(w * 0.72, h * 0.40)
            let glowSize = circleSize * 1.13
            
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.95, blue: 0.98),
                        Color(red: 0.96, green: 0.94, blue: 0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
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
                            .fill(Color.white.opacity(0.95))
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
                            .fill(Color.white.opacity(0.85))
                            .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
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
    let image: UIImage
    
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
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.07),
                        Color.purple.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
                .foregroundStyle(Color(white: 0.3))
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Analysis Overlay
private struct AnalysisOverlay: View {
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            // Analysis indicator
            VStack(spacing: AppSpacing.m) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                
                Text("Analyzing Your Smile")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                
                Text("This will just take a moment...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
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
            .background(isSelected ? Color.blue.opacity(0.12) : Color.white)
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


