import SwiftUI
import UIKit

struct OnboardingView: View {
    private enum Step {
        case intro
        case capture
        case preview
        case loading
        case auth
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.authRepository) private var authRepository
    @EnvironmentObject private var scanSession: ScanSession
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var step: Step = .intro
    @State private var showCamera = false
    @State private var capturedImageData: Data?
    @State private var isSigningIn = false
    @State private var signInError: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [AppColors.card, AppColors.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.l) {
                Text("Gleam")
                    .font(.largeTitle).bold()
                switch step {
                case .intro, .capture:
                    introContent
                case .preview:
                    previewContent
                case .loading:
                    loadingContent
                case .auth:
                    authContent
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.bottom, AppSpacing.l)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { data in
                if let data {
                    capturedImageData = data
                    step = .preview
                } else {
                    step = .intro
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .alert("Sign in failed", isPresented: Binding(
            get: { signInError != nil },
            set: { value in if !value { signInError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInError ?? "Unknown error")
        }
    }

    private var introContent: some View {
        VStack(spacing: AppSpacing.l) {
            Text("Ready to make them gleam?")
                .font(.title2)
                .multilineTextAlignment(.center)

            VStack(spacing: AppSpacing.s) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 72))
                Text("We’ll guide you through capture, preview, and your custom plan.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                step = .capture
                showCamera = true
            } label: {
                Text("Scan your smile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var previewContent: some View {
        VStack(spacing: AppSpacing.m) {
            if let data = capturedImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    .frame(maxHeight: 280)
            }

            Text("Looking great! Ready for your plan?")
                .font(.title3)
                .multilineTextAlignment(.center)

            Button {
                step = .loading
                prepareForAuthentication()
            } label: {
                Text("Make them Gleam")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                step = .capture
                showCamera = true
            } label: {
                Text("Retake photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var loadingContent: some View {
        VStack(spacing: AppSpacing.m) {
            GleamLoadingView()
            Text("Getting things ready...")
                .font(.headline)
        }
        .task { await pauseAndAdvance() }
    }

    private var authContent: some View {
        VStack(spacing: AppSpacing.m) {
            Text("Sign in to unlock your personalized plan.")
                .multilineTextAlignment(.center)

            if isSigningIn {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack(spacing: AppSpacing.s) {
                        Image(systemName: "sparkles")
                Text("Continue with Google")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button("Back") {
                step = .preview
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func prepareForAuthentication() {
        Task {
            await pauseAndAdvance()
        }
    }

    @MainActor
    private func signIn() async {
        guard let presentingController = currentPresenter() else {
            signInError = "Unable to find presenter."
            return
        }

        isSigningIn = true
        do {
            try await authRepository.signInWithGoogle(presentingController: presentingController)
            finishOnboarding()
        } catch {
            signInError = error.localizedDescription
            isSigningIn = false
        }
    }

    private func pauseAndAdvance() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        await MainActor.run { step = .auth }
    }

    @MainActor
    private func finishOnboarding() {
        guard let data = capturedImageData else {
            signInError = "Capture a photo before continuing."
            isSigningIn = false
            return
        }

        scanSession.capturedImageData = data
        scanSession.shouldOpenCamera = false
        didCompleteOnboarding = true
        dismiss()
    }

    private func currentPresenter() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return nil }

        var controller: UIViewController = root
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }
}


