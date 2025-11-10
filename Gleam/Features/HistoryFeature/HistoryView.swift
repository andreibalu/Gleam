import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var averageMode: AverageMode = .last5
    @State private var showAveragePicker: Bool = false

    var body: some View {
        Group {
            if historyStore.items.isEmpty {
                VStack(spacing: AppSpacing.s) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No history yet")
                        .font(.headline)
                    Text("Run a scan to see your whitening insights here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.l) {
                        HistoryHighlightsView(
                            currentStreak: historyStore.currentStreak,
                            bestStreak: historyStore.bestStreak,
                            averageScore: averageScoreSelected ?? 0,
                            averageAvailable: averageScoreSelected != nil,
                            averageMode: averageMode,
                            onAverageTap: { showAveragePicker = true },
                            latestScore: latestScore,
                            latestShade: historyStore.items.first?.result.shade ?? ""
                        )

                        LazyVStack(spacing: AppSpacing.m, pinnedViews: []) {
                            ForEach(historyStore.items) { item in
                                NavigationLink(value: item.result) {
                                    HistoryCardView(item: item, historyStore: historyStore)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await historyStore.delete(item) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await historyStore.delete(item) }
                                    } label: {
                                        Label("Delete scan", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(AppColors.background.ignoresSafeArea())
                .confirmationDialog("Average window", isPresented: $showAveragePicker, titleVisibility: .visible) {
                    Button(AverageMode.last5.menuTitle) { averageMode = .last5 }
                    Button(AverageMode.last7Days.menuTitle) { averageMode = .last7Days }
                    Button(AverageMode.last30Days.menuTitle) { averageMode = .last30Days }
                }
            }
        }
        .navigationTitle("History")
        .task { await historyStore.load() }
    }

    private var averageScoreSelected: Double? {
        averageScore(for: averageMode)
    }

    private var latestScore: Double {
        guard let latest = historyStore.items.first else { return 0 }
        return Double(latest.result.whitenessScore) / 10.0
    }

    private func averageScore(for mode: AverageMode) -> Double? {
        guard !historyStore.items.isEmpty else { return nil }
        let now = Date()
        let filtered: [HistoryItem]
        switch mode {
        case .last5:
            filtered = Array(historyStore.items.prefix(5))
        case .last7Days:
            if let start = Calendar.current.date(byAdding: .day, value: -7, to: now) {
                filtered = historyStore.items.filter { $0.createdAt >= start }
            } else {
                filtered = []
            }
        case .last30Days:
            if let start = Calendar.current.date(byAdding: .day, value: -30, to: now) {
                filtered = historyStore.items.filter { $0.createdAt >= start }
            } else {
                filtered = []
            }
        }
        guard !filtered.isEmpty else { return nil }
        let total = filtered.reduce(0.0) { partial, item in
            partial + (Double(item.result.whitenessScore) / 10.0)
        }
        return total / Double(filtered.count)
    }
}

private struct HistoryHighlightsView: View {
    let currentStreak: Int
    let bestStreak: Int
    let averageScore: Double
    let averageAvailable: Bool
    let averageMode: AverageMode
    let onAverageTap: () -> Void
    let latestScore: Double
    let latestShade: String

    private var shadeDescription: String {
        let shadeMap: [String: String] = [
            "A1": "Very Light", "A2": "Light", "A3": "Medium-Light",
            "B1": "Light", "B2": "Medium-Light", "B3": "Medium",
            "C1": "Light", "C2": "Medium", "C3": "Medium-Dark",
            "D2": "Medium", "D3": "Medium-Dark", "D4": "Dark"
        ]
        return shadeMap[latestShade.uppercased()] ?? latestShade.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Your whitening journey")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HighlightMetric(
                    title: "Latest Score",
                    value: String(format: "%.1f", latestScore),
                    caption: shadeDescription,
                    icon: "sparkle.magnifyingglass",
                    tint: .blue
                )

                HighlightMetric(
                    title: "Current Streak",
                    value: "\(currentStreak)",
                    caption: "Best \(bestStreak)",
                    icon: "flame.fill",
                    tint: currentStreak > 0 ? .orange : .gray
                )

                if averageAvailable {
                    HighlightMetric(
                        title: "Average",
                        value: String(format: "%.1f", averageScore),
                        caption: averageMode.caption,
                        icon: "chart.line.uptrend.xyaxis",
                        tint: .green,
                        onTitleTap: onAverageTap
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

private struct HighlightMetric: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color
    var onTitleTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                if let onTitleTap {
                    Button(action: onTitleTap) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.65))
        )
    }
}

private enum AverageMode: CaseIterable {
    case last5
    case last7Days
    case last30Days

    var caption: String {
        switch self {
        case .last5: return "Across last 5 scans"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        }
    }

    var menuTitle: String {
        switch self {
        case .last5: return "Average of last 5 scans"
        case .last7Days: return "Average over last 7 days"
        case .last30Days: return "Average over last 30 days"
        }
    }
}

private struct HistoryCardView: View {
    let item: HistoryItem
    let historyStore: HistoryStore
    @State private var imageData: Data? = nil
    
    private var formattedDate: String {
        DateFormatter.historyFormatter.string(from: item.createdAt)
    }
    
    private var normalizedScore: Double {
        Double(item.result.whitenessScore) / 10.0
    }
    
    private var shadeDescription: String {
        let shadeMap: [String: String] = [
            "A1": "Very Light", "A2": "Light", "A3": "Medium-Light",
            "B1": "Light", "B2": "Medium-Light", "B3": "Medium",
            "C1": "Light", "C2": "Medium", "C3": "Medium-Dark",
            "D2": "Medium", "D3": "Medium-Dark", "D4": "Dark"
        ]
        return shadeMap[item.result.shade] ?? item.result.shade
    }

    private var scoreColor: Color {
        if normalizedScore >= 8.0 { return .green }
        if normalizedScore >= 6.0 { return .blue }
        if normalizedScore >= 4.0 { return .orange }
        return .red
    }
    
    private var scoreLabel: String {
        if normalizedScore >= 9.0 { return "Brilliant" }
        if normalizedScore >= 8.0 { return "Excellent" }
        if normalizedScore >= 7.0 { return "Great" }
        if normalizedScore >= 6.0 { return "Good" }
        if normalizedScore >= 5.0 { return "Improving" }
        if normalizedScore >= 3.0 { return "Keep Going" }
        return "Start Here"
    }
    
    private var scoreEmoji: String {
        if normalizedScore >= 9.0 { return "✨" }
        if normalizedScore >= 8.0 { return "🌟" }
        if normalizedScore >= 7.0 { return "🎯" }
        if normalizedScore >= 6.0 { return "👍" }
        if normalizedScore >= 5.0 { return "📈" }
        if normalizedScore >= 3.0 { return "💪" }
        return "🚀"
    }

    private var tagTitles: [String] {
        item.contextTags.compactMap { StainTag.title(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                ScoreBadge(normalizedScore: normalizedScore, scoreColor: scoreColor, scoreEmoji: scoreEmoji, scoreLabel: scoreLabel)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(shadeDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                ScanPhotoView(imageData: imageData)
            }

            if !tagTitles.isEmpty {
                LifestyleTagRow(tags: tagTitles)
            }

            if !item.result.personalTakeaway.isEmpty {
                Text(item.result.personalTakeaway)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
        .task {
            imageData = await historyStore.loadImage(for: item.id)
        }
    }
}

private struct ScoreBadge: View {
    let normalizedScore: Double
    let scoreColor: Color
    let scoreEmoji: String
    let scoreLabel: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: normalizedScore / 10.0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", normalizedScore))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text(scoreEmoji)
                        .font(.callout)
                }
            }
            .frame(width: 90, height: 90)

            Text(scoreLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanPhotoView: View {
    let imageData: Data?

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.gray.opacity(0.5))
                            .font(.title3)
                    }
            }
        }
    }
}

private struct LifestyleTagRow: View {
    let tags: [String]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 90), spacing: AppSpacing.s)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
            ForEach(tags, id: \.self) { tag in
                LifestyleTagPill(label: tag)
            }
        }
    }
}

private struct LifestyleTagPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xs)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}

private extension DateFormatter {
    static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}


