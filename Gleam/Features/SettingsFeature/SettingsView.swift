import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var scanSession: ScanSession
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @State private var showResetAlert: Bool = false
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
    }
}


