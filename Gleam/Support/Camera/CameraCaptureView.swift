import PhotosUI
import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
  @Environment(\.dismiss) private var dismiss
  let onImageCaptured: (CaptureResult?) -> Void

  func makeUIViewController(context: Context) -> UIViewController {
    #if targetEnvironment(simulator)
    let picker = PHPickerViewController(configuration: {
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      return config
    }())
    picker.delegate = context.coordinator
    return picker
    #else
    let host = UIHostingController(rootView:
      TeethCameraView { result in
        onImageCaptured(result)
      }
    )
    host.modalPresentationStyle = .fullScreen
    return host
    #endif
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let parent: CameraCaptureView

    init(_ parent: CameraCaptureView) {
      self.parent = parent
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard let result = results.first else {
        DispatchQueue.main.async {
          self.parent.onImageCaptured(nil)
        }
        return
      }

      result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
        guard let self else { return }

        guard let image = object as? UIImage else {
          DispatchQueue.main.async {
            self.parent.onImageCaptured(nil)
          }
          return
        }

        let data = self.compressImage(image)
        DispatchQueue.main.async {
          if let data {
            self.parent.onImageCaptured(CaptureResult(imageData: data, teethMatte: nil))
          } else {
            self.parent.onImageCaptured(nil)
          }
        }
      }
    }

    private func compressImage(_ image: UIImage) -> Data? {
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
}
