import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var page: Int = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [AppColors.card, AppColors.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.l) {
                Text("Gleam")
                    .font(.largeTitle).bold()
                TabView(selection: $page) {
                    OnboardingSlide(
                        title: "Scan",
                        subtitle: "Analyze your smile with a quick photo.",
                        systemImage: "camera.viewfinder"
                    ).tag(0)
                    OnboardingSlide(
                        title: "Private",
                        subtitle: "Your images are private and never shared.",
                        systemImage: "lock.shield"
                    ).tag(1)
                    OnboardingSlide(
                        title: "Plan",
                        subtitle: "Get a personalized whitening plan.",
                        systemImage: "sparkles"
                    ).tag(2)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(action: complete) {
                    Text(page < 2 ? "Next" : "Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.m)
            }
            .padding()
        }
    }

    private func complete() {
        if page < 2 {
            withAnimation { page += 1 }
        } else {
            didCompleteOnboarding = true
            dismiss()
        }
    }
}

private struct OnboardingSlide: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
            Text(title)
                .font(.title).bold()
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}


