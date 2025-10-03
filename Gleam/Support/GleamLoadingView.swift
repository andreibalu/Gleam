import SwiftUI

struct GleamLoadingView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppColors.card)
                    .frame(width: 12, height: 12)
                    .scaleEffect(animate ? 1 : 0.5)
                    .opacity(animate ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(AppSpacing.s)
        .background(AppColors.background.opacity(0.3))
        .clipShape(Capsule())
        .onAppear { animate = true }
    }
}
