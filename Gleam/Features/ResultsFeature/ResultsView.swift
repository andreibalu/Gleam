import SwiftUI

struct ResultsView: View {
    let result: ScanResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                ScoreRing(score: normalizedScore(result.whitenessScore))
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)

                GroupBox("Shade Classification") {
                    HStack {
                        Label(shadeDescription, systemImage: "eyedropper")
                            .font(.subheadline)
                        Spacer()
                        Text(result.shade)
                            .foregroundStyle(.secondary)
                            .font(.caption)
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
    
    private func normalizedScore(_ rawScore: Int) -> Double {
        // Convert 0-100 to 0-10 scale
        return Double(rawScore) / 10.0
    }
    
    private var shadeDescription: String {
        // Simplified shade description
        let shadeMap: [String: String] = [
            "A1": "Very Light", "A2": "Light", "A3": "Medium-Light",
            "B1": "Light", "B2": "Medium-Light", "B3": "Medium",
            "C1": "Light", "C2": "Medium", "C3": "Medium-Dark",
            "D2": "Medium", "D3": "Medium-Dark", "D4": "Dark"
        ]
        return shadeMap[result.shade] ?? result.shade
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
    let score: Double // 0-10 scale
    @State private var animatedScore: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 20)
            Circle()
                .trim(from: 0, to: min(1.0, animatedScore / 10.0))
                .stroke(scoreGradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.0, dampingFraction: 0.7), value: animatedScore)
            
            VStack(spacing: 4) {
                Text(String(format: "%.1f", animatedScore))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreGradient)
                    .contentTransition(.numericText(value: animatedScore))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: animatedScore)
                
                Text("/ 10")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                Text(scoreLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(scoreLabelColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(scoreLabelColor.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2)) {
                animatedScore = score
            }
        }
    }
    
    private var scoreGradient: LinearGradient {
        let colors: [Color]
        if animatedScore >= 8.0 {
            colors = [.green, .mint]
        } else if animatedScore >= 6.0 {
            colors = [.blue, .cyan]
        } else if animatedScore >= 4.0 {
            colors = [.orange, .yellow]
        } else {
            colors = [.red, .orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var scoreLabel: String {
        if animatedScore >= 9.0 { return "✨ Brilliant" }
        if animatedScore >= 8.0 { return "🌟 Excellent" }
        if animatedScore >= 7.0 { return "🎯 Great" }
        if animatedScore >= 6.0 { return "👍 Good" }
        if animatedScore >= 5.0 { return "📈 Improving" }
        if animatedScore >= 3.0 { return "💪 Keep Going" }
        return "🚀 Start Here"
    }
    
    private var scoreLabelColor: Color {
        if animatedScore >= 8.0 { return .green }
        if animatedScore >= 6.0 { return .blue }
        if animatedScore >= 4.0 { return .orange }
        return .red
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


