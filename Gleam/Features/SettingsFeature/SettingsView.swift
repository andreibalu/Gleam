import SwiftUI

struct SettingsView: View {
    @Environment(\.authRepository) private var authRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var showSignOutAlert: Bool = false
    @State private var showDeleteAccountAlert: Bool = false
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                Toggle(isOn: $isDarkMode) {
                    Text("Dark Mode")
                }
            }
            Section(header: Text("Privacy")) {
                Link("Privacy Policy", destination: URL(string: "https://gen-lang-client-0740636332.web.app/privacy.html")!)
                Link("Terms of Service", destination: URL(string: "https://gen-lang-client-0740636332.web.app/terms.html")!)
            }
            Section(header: Text("Account")) {
                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    Text("Sign Out")
                }
                Button(role: .destructive) {
                    showDeleteAccountAlert = true
                } label: {
                    if isDeleting {
                        HStack {
                            Text("Deleting account...")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Delete my account")
                    }
                }
                .disabled(isDeleting)
            }
            Section(header: Text("Onboarding")) {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text("Reset onboarding")
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Reset onboarding?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                didCompleteOnboarding = false
                scanSession.reset()
            }
        } message: {
            Text("You'll see onboarding the next time you use Gleam.")
        }
        .alert("Sign out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                performSignOut()
            }
        } message: {
            Text("You'll need to sign in again to use Gleam.")
        }
        .alert("Delete your account?", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text("This will permanently delete your account and all your data. This action cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func performSignOut() {
        do {
            try authRepository.signOut()
            didCompleteOnboarding = false
            scanSession.reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performDeleteAccount() async {
        isDeleting = true
        do {
            try await authRepository.deleteAccount()
            await historyStore.clearAll()
            didCompleteOnboarding = false
            scanSession.reset()
        } catch {
            let nsError = error as NSError
            if nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17014 {
                errorMessage = "For security, please sign out and sign back in before deleting your account."
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isDeleting = false
    }
}


