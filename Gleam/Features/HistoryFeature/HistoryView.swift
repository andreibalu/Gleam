import SwiftUI

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
                    ForEach(historyStore.items) { item in
                        NavigationLink(destination: ResultsView(result: item.result)) {
                            HistoryRowView(result: item.result, createdAt: item.createdAt)
                        }
                    }
                    .onDelete(perform: delete)
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
    let result: ScanResult
    let createdAt: Date

    private var formattedDate: String {
        DateFormatter.historyFormatter.string(from: createdAt)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Score: \(result.whitenessScore)")
                    .font(.headline)
                Text("Shade: \(result.shade)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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


