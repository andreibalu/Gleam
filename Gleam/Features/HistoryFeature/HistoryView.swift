import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var historyStore: HistoryStore

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
                List {
                    // Streak Section
                    Section {
                        HStack(spacing: AppSpacing.m) {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(historyStore.currentStreak > 0 ? .orange : .gray)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(historyStore.currentStreak)")
                                        .font(.title2.bold())
                                    Text("Current Streak")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Divider()
                            
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(historyStore.bestStreak)")
                                        .font(.title2.bold())
                                    Text("Best Streak")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, AppSpacing.s)
                    }
                    
                    // History Items
                    Section {
                        ForEach(historyStore.items) { item in
                            NavigationLink(value: item.result) {
                                HistoryRowView(item: item, historyStore: historyStore)
                            }
                        }
                        .onDelete(perform: delete)
                    } header: {
                        Text("Your Scans")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .task { await historyStore.load() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let item = historyStore.items[index]
            Task { await historyStore.delete(item) }
        }
    }
}

private struct HistoryRowView: View {
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

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            // Score Circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: normalizedScore / 10.0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.1f", normalizedScore))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
            }
            .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(scoreEmoji)
                        .font(.title3)
                    Text(scoreLabel)
                        .font(.headline)
                }
                Text(shadeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Scan Photo
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    }
            } else {
                // Placeholder when image not available
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.gray.opacity(0.5))
                            .font(.caption)
                    }
            }
        }
        .padding(.vertical, 4)
        .task {
            // Load image asynchronously
            imageData = await historyStore.loadImage(for: item.id)
        }
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
}

private extension DateFormatter {
    static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}


