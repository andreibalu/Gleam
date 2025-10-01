import SwiftUI

struct HomeView: View {
    @Environment(\.scanRepository) private var scanRepository
    @State private var isScanning = false
    @State private var lastResult: ScanResult? = nil
    var onScanTapped: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.l) {
                VStack(spacing: AppSpacing.s) {
                    Text("Gleam")
                        .font(.largeTitle).bold()
                    Text("Personalized whitening insights")
                        .foregroundStyle(AppColors.secondary)
                }
                .padding(.top, AppSpacing.xl)

                Button(action: onScanTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Scan your smile")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("home_scan_button")

                if let result = lastResult {
                    LastResultCard(result: result)
                        .accessibilityIdentifier("home_last_result")
                }
            }
            .padding(.horizontal, AppSpacing.m)
        }
        .background(AppColors.background.ignoresSafeArea())
        .task {
            do { lastResult = try await scanRepository.fetchLatest() } catch { }
        }
    }
}

private struct LastResultCard: View {
    let result: ScanResult
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text("Last result").font(.headline)
                Spacer()
                Text("\(result.whitenessScore)")
                    .font(.title2).bold()
            }
            HStack(spacing: AppSpacing.s) {
                Label(result.shade, systemImage: "eyedropper.halffull")
                Text("Conf: \(Int(result.confidence * 100))%")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}


