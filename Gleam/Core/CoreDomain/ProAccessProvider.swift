import Foundation
import Combine

final class ProAccessProvider: ObservableObject {
    private static let devOverrideKey = "dev_pro_override"

    @Published var isPro: Bool {
        didSet {
            UserDefaults.standard.set(isPro, forKey: Self.devOverrideKey)
        }
    }

    init() {
        self.isPro = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
    }
}
