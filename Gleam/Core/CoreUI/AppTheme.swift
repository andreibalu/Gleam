import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appTheme"
    static let legacyKey = "isDarkMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func migrateLegacySettingIfNeeded(userDefaults: UserDefaults = .standard) {
        guard userDefaults.object(forKey: storageKey) == nil else { return }
        guard let legacyValue = userDefaults.object(forKey: legacyKey) as? Bool else { return }
        userDefaults.set(legacyValue ? AppTheme.dark.rawValue : AppTheme.light.rawValue, forKey: storageKey)
    }
}
