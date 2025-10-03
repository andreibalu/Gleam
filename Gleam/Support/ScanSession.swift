import SwiftUI
import Combine

final class ScanSession: ObservableObject {
    @Published var capturedImageData: Data?
    @Published var shouldOpenCamera: Bool = false
    
    func reset() {
        capturedImageData = nil
        shouldOpenCamera = false
    }
}
