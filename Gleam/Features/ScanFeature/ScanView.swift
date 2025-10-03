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
                            Text("No photo selected")
                        }
                        .foregroundStyle(.secondary)
                    }
            }

            if selectedImageData == nil {
                Button {
                    scanSession.shouldOpenCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Take photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("scan_take_photo_button")

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Choose from library")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadImage(from: newItem) }
                }
            } else {
                Button {
                    scanSession.shouldOpenCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Take a new photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("scan_take_new_photo_button")

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Choose different photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadImage(from: newItem) }
                }
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
        .onAppear {
            if let capturedData = scanSession.capturedImageData {
                selectedImageData = capturedData
                scanSession.capturedImageData = nil
            }
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
            historyStore.append(result)
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


