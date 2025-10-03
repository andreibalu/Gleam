import SwiftUI
import UIKit
import PhotosUI

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImageCaptured: (Data?) -> Void
    
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
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = context.coordinator
            return picker
        } else {
            let picker = PHPickerViewController(configuration: {
                var config = PHPickerConfiguration()
                config.filter = .images
                config.selectionLimit = 1
                return config
            }())
            picker.delegate = context.coordinator
            return picker
        }
        #endif
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
        let parent: CameraCaptureView
        
        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                let data = compressImage(image)
                parent.onImageCaptured(data)
            } else {
                parent.onImageCaptured(nil)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImageCaptured(nil)
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onImageCaptured(nil)
                return
            }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                guard let self = self, let image = object as? UIImage else {
                    DispatchQueue.main.async {
                        self?.parent.onImageCaptured(nil)
                    }
                    return
                }
                
                let data = self.compressImage(image)
                DispatchQueue.main.async {
                    self.parent.onImageCaptured(data)
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
