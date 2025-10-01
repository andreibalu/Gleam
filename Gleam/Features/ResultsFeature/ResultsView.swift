import SwiftUI

struct ResultsView: View {
    let result: ScanResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                ScoreRing(score: result.whitenessScore)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)

                GroupBox("Shade & Confidence") {
                    HStack {
                        Label(result.shade, systemImage: "eyedropper")
                        Spacer()
                        Text("\(Int(result.confidence * 100))%")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Detected Issues") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        ForEach(result.detectedIssues, id: \.key) { issue in
                            HStack {
                                Text(issue.key.capitalized)
                                Spacer()
                                Text(issue.severity)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Plan") {
                    PlanSection(title: "Immediate", items: result.recommendations.immediate)
                    PlanSection(title: "Daily", items: result.recommendations.daily)
                    PlanSection(title: "Weekly", items: result.recommendations.weekly)
                    PlanSection(title: "Caution", items: result.recommendations.caution)
                }

                ShareLink(item: shareText(for: result)) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Text(result.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Results")
        .background(AppColors.background.ignoresSafeArea())
    }
}

private struct PlanSection: View {
    let title: String
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(title).font(.headline)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(item)
                    }
                }
            }
            .padding(.vertical, AppSpacing.s)
        }
    }
}

private struct ScoreRing: View {
    let score: Int
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 16)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, Double(score)/100))))
                .stroke(AppColors.primary, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)
            Text("\(score)")
                .font(.largeTitle).bold()
        }
    }
}

private func shareText(for result: ScanResult) -> String {
    var lines: [String] = []
    lines.append("Gleam Whitening Summary")
    lines.append("Score: \(result.whitenessScore)")
    lines.append("Shade: \(result.shade)")
    if !result.recommendations.immediate.isEmpty { lines.append("Immediate: \(result.recommendations.immediate.joined(separator: ", "))") }
    if !result.recommendations.daily.isEmpty { lines.append("Daily: \(result.recommendations.daily.joined(separator: ", "))") }
    if !result.recommendations.weekly.isEmpty { lines.append("Weekly: \(result.recommendations.weekly.joined(separator: ", "))") }
    if !result.recommendations.caution.isEmpty { lines.append("Caution: \(result.recommendations.caution.joined(separator: ", "))") }
    return lines.joined(separator: "\n")
}


