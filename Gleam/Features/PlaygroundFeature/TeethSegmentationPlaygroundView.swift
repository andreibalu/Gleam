import PhotosUI
import SwiftUI
import UIKit

struct TeethSegmentationPlaygroundView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var sample: TeethPlaygroundSample?
    @State private var analysis: TeethPlaygroundAnalysis?
    @State private var showCamera: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                introCard
                captureControls
                samplePreview
                analyzeButton

                if let analysis {
                    analysisPanel(analysis)
                }
            }
            .padding(AppSpacing.m)
        }
        .background(AppBackground())
        .navigationTitle("Teeth Playground")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showCamera) {
            TeethMatteCaptureView(
                onCapture: { captured in
                    sample = captured
                    analysis = nil
                    showCamera = false
                },
                onCancel: {
                    showCamera = false
                },
                onError: { message in
                    showCamera = false
                    errorMessage = message
                }
            )
            .ignoresSafeArea()
        }
        .alert("Playground", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await loadLibrarySample(from: newValue)
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("Local segmentation playground")
                .font(.headline)
            Text("This isolated lab uses AVSemanticSegmentationMatte (.teeth) and on-device heuristics only. No GPT calls and no ScanView logic.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Goal: validate a replacement scanning pipeline end-to-end before touching production flow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
        )
    }

    private var captureControls: some View {
        VStack(spacing: AppSpacing.s) {
            Button {
                showCamera = true
            } label: {
                Label("Playground Camera (Matte)", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(FloatingPrimaryButtonStyle())

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Import Photo (extract embedded matte if available)", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(FloatingSecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var samplePreview: some View {
        if let sample {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                ZStack {
                    Image(uiImage: sample.photo)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    if let teethMask = sample.teethMask {
                        Image(uiImage: teethMask)
                            .resizable()
                            .scaledToFit()
                            .colorMultiply(.cyan)
                            .opacity(0.45)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            .blendMode(.screen)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

                HStack(spacing: AppSpacing.s) {
                    Text(sample.sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sample.hasSemanticTeethMatte ? "Teeth matte detected" : "No teeth matte")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sample.hasSemanticTeethMatte ? .green : .orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((sample.hasSemanticTeethMatte ? Color.green : Color.orange).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColors.card)
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("No sample yet")
                    .font(.headline)
                Text("Capture through Playground Camera for best chance of receiving AVSemanticSegmentationMatte(.teeth).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColors.card)
            )
        }
    }

    private var analyzeButton: some View {
        Button {
            analyzeSample()
        } label: {
            HStack(spacing: AppSpacing.s) {
                if isAnalyzing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "cpu")
                }
                Text(isAnalyzing ? "Analyzing locally..." : "Run Local Score + Shade Analysis")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(FloatingPrimaryButtonStyle())
        .disabled(sample == nil || isAnalyzing)
        .opacity((sample == nil || isAnalyzing) ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func analysisPanel(_ analysis: TeethPlaygroundAnalysis) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playground Result")
                        .font(.headline)
                    Text("Whiteness score: \(analysis.result.whitenessScore)")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Shade \(analysis.result.shade)")
                        .font(.headline)
                    Text("\(Int((analysis.result.confidence * 100).rounded()))% confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Technical metrics")
                    .font(.subheadline.weight(.semibold))
                metricRow("Teeth coverage", value: String(format: "%.2f%%", analysis.metrics.maskCoverage * 100))
                metricRow("Segmented pixels", value: "\(analysis.metrics.segmentedPixelCount)")
                metricRow("L* (lightness)", value: String(format: "%.2f", analysis.metrics.averageLightness))
                metricRow("a* (green-red)", value: String(format: "%.2f", analysis.metrics.averageA))
                metricRow("b* (blue-yellow)", value: String(format: "%.2f", analysis.metrics.averageB))
                metricRow("Lightness std dev", value: String(format: "%.2f", analysis.metrics.lightnessStdDev))
                metricRow("Uniformity", value: String(format: "%.2f", analysis.metrics.uniformity))
            }

            if !analysis.result.detectedIssues.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text("Detected focus areas")
                        .font(.subheadline.weight(.semibold))
                    ForEach(analysis.result.detectedIssues, id: \.self) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(issue.key.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(issue.severity.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(severityColor(issue.severity).opacity(0.14))
                                    .foregroundStyle(severityColor(issue.severity))
                                    .clipShape(Capsule())
                            }
                            Text(issue.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemBackground))
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Takeaway")
                    .font(.subheadline.weight(.semibold))
                Text(analysis.result.personalTakeaway)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(analysis.result.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
        )
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    private func analyzeSample() {
        guard let sample else {
            errorMessage = TeethPlaygroundAnalysisError.noImage.localizedDescription
            return
        }

        isAnalyzing = true
        analysis = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let analyzer = TeethPlaygroundAnalyzer()
            do {
                let result = try analyzer.analyze(sample: sample)
                DispatchQueue.main.async {
                    analysis = result
                    isAnalyzing = false
                }
            } catch {
                DispatchQueue.main.async {
                    isAnalyzing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadLibrarySample(from item: PhotosPickerItem) async {
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let uiImage = UIImage(data: data)
            else {
                await MainActor.run {
                    errorMessage = "Unable to load this image."
                }
                return
            }

            let normalizedPhoto = TeethPlaygroundImagePipeline.normalizedPhoto(uiImage)
            let extractedMask = TeethPlaygroundImagePipeline.extractTeethMask(from: data)
            let alignedMask = extractedMask.map {
                TeethPlaygroundImagePipeline.normalizedMask($0, targetSize: normalizedPhoto.size)
            }

            await MainActor.run {
                sample = TeethPlaygroundSample(
                    photo: normalizedPhoto,
                    teethMask: alignedMask,
                    sourceDescription: alignedMask == nil
                        ? "Photo library (no embedded teeth matte)"
                        : "Photo library (embedded AVSemanticSegmentationMatte teeth)",
                    hasSemanticTeethMatte: alignedMask != nil
                )
                analysis = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to import image from library."
            }
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .blue
        }
    }
}

