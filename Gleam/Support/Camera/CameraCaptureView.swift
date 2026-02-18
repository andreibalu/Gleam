import CoreImage
import PhotosUI
import SwiftUI
import UIKit

struct CameraCaptureView: View {
    struct CaptureResult {
        let imageData: Data
        let teethMatte: CIImage?
    }

    let onImageCaptured: (CaptureResult?) -> Void

    var body: some View {
        #if targetEnvironment(simulator)
        CameraLibraryPicker { data in
            guard let data else {
                onImageCaptured(nil)
                return
            }
            onImageCaptured(CaptureResult(imageData: data, teethMatte: nil))
        }
        #else
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            TeethCaptureSession(
                onCapture: { imageData, teethMatte in
                    guard let compressedData = Self.compressImageData(imageData) else {
                        onImageCaptured(nil)
                        return
                    }
                    onImageCaptured(CaptureResult(imageData: compressedData, teethMatte: teethMatte))
                },
                onCancel: {
                    onImageCaptured(nil)
                }
            )
        } else {
            CameraLibraryPicker { data in
                guard let data else {
                    onImageCaptured(nil)
                    return
                }
                onImageCaptured(CaptureResult(imageData: data, teethMatte: nil))
            }
        }
        #endif
    }

    static func compressImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return compressImage(image)
    }

    static func compressImage(_ image: UIImage) -> Data? {
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

private struct CameraLibraryPicker: UIViewControllerRepresentable {
    let onImageCaptured: (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImageCaptured: (Data?) -> Void

        init(onImageCaptured: @escaping (Data?) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                DispatchQueue.main.async {
                    self.onImageCaptured(nil)
                }
                return
            }

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else {
                    DispatchQueue.main.async {
                        self.onImageCaptured(nil)
                    }
                    return
                }

                let data = CameraCaptureView.compressImage(image)
                DispatchQueue.main.async {
                    self.onImageCaptured(data)
                }
            }
        }
    }
}
