import SwiftUI
import Combine

final class ScanSession: ObservableObject {
    @Published var capturedImageData: Data?
    @Published var shouldOpenCamera: Bool = false
    @Published var shouldOpenHistory: Bool = false
    
    func reset() {
        capturedImageData = nil
        shouldOpenCamera = false
        shouldOpenHistory = false
    }
}
