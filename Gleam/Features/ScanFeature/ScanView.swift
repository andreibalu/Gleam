import SwiftUI
import PhotosUI
import UIKit

struct ScanView: View {
    @Environment(\.scanRepository) private var scanRepository
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isAnalyzing = false
    @State private var analysisResult: ScanResult? = nil

    var onFinished: (ScanResult) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .frame(maxHeight: 280)
            } else {
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.card)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                            Text("Pick a photo")
                        }
                        .foregroundStyle(.secondary)
                    }
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("Choose Photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .onChange(of: photoItem) { _, newItem in
                Task { await loadImage(from: newItem) }
            }

            Button("Analyze") {
                Task { await analyze() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedImageData == nil || isAnalyzing)

            Spacer()
        }
        .padding()
        .overlay {
            if isAnalyzing { ProgressView("Analyzing...") }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = compressImageDataIfNeeded(data)
            }
        } catch { }
    }

    private func analyze() async {
        guard let data = selectedImageData else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let result = try await scanRepository.analyze(imageData: data)
            analysisResult = result
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


