import SwiftUI

struct HomeView: View {
    @Environment(\.scanRepository) private var scanRepository
    @EnvironmentObject private var scanSession: ScanSession
    @State private var isScanning = false
    @State private var lastResult: ScanResult? = nil
    @State private var showCamera = false

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

                Button {
                    showCamera = true
                } label: {
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
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { data in
                scanSession.capturedImageData = data
                showCamera = false
            }
            .accessibilityIdentifier("camera_sheet")
            .ignoresSafeArea()
        }
        .task {
            do { lastResult = try await scanRepository.fetchLatest() } catch { }
        }
        .onChange(of: scanSession.shouldOpenCamera) { _, shouldOpen in
            if shouldOpen {
                showCamera = true
                scanSession.shouldOpenCamera = false
            }
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


