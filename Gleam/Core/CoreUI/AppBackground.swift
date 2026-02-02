import SwiftUI

/// A shared background view that provides a consistent gradient across all tabs.
/// In dark mode, it renders a subtle purple-tinted glow.
/// In light mode, it renders a near-white subtle gradient.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private var gradient: LinearGradient {
        let lightColors = [
            Color(red: 0.95, green: 0.97, blue: 1.0),
            Color(red: 0.98, green: 0.95, blue: 1.0)
        ]
        let darkColors = [
            Color(red: 0.06, green: 0.07, blue: 0.11),
            Color(red: 0.11, green: 0.09, blue: 0.16)
        ]
        return LinearGradient(
            colors: colorScheme == .dark ? darkColors : lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        gradient
            .ignoresSafeArea()
    }
}
