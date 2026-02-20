import Combine
import CoreImage
import SwiftUI

final class ScanSession: ObservableObject {
  @Published var capturedImageData: Data?
  @Published var capturedTeethMatte: CIImage?
  @Published var shouldOpenCamera: Bool = false
  @Published var shouldOpenHistory: Bool = false

  func reset() {
    capturedImageData = nil
    capturedTeethMatte = nil
    shouldOpenCamera = false
    shouldOpenHistory = false
  }
}
