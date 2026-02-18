import SwiftUI
import Combine
import CoreImage

final class ScanSession: ObservableObject {
    @Published var capturedImageData: Data?
    @Published var capturedTeethMatte: CIImage? = nil
    @Published var shouldOpenCamera: Bool = false
    @Published var shouldOpenHistory: Bool = false
    
    func reset() {
        capturedImageData = nil
        capturedTeethMatte = nil
        shouldOpenCamera = false
        shouldOpenHistory = false
    }
}
