import SwiftUI

struct SettingsView: View {
    @Environment(\.authRepository) private var authRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @AppStorage(AppTheme.storageKey) private var themeRawValue: String = AppTheme.system.rawValue
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var showSignOutAlert: Bool = false
    @State private var showDeleteAccountAlert: Bool = false
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var isRestoring = false

    private var themeSelection: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: themeRawValue) ?? .system },
            set: { themeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(header: Text("Gleam Pro")) {
                if subscriptionManager.isPremium {
                    HStack {
                        Label("Gleam Pro", systemImage: "crown.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 0.95)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        Spacer()
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Manage Subscription") {
                        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Upgrade to Gleam Pro", systemImage: "crown")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.3, blue: 0.95)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    }
                    Button {
                        Task {
                            isRestoring = true
                            await subscriptionManager.restorePurchases()
                            isRestoring = false
                        }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            if isRestoring { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRestoring)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }

            Section(header: Text("Appearance")) {
                Picker("Theme", selection: themeSelection) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
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
        .scrollContentBackground(.hidden)
        .background(AppBackground())
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


