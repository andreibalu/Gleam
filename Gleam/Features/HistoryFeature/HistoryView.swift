import SwiftUI

struct HistoryView: View {
    @State private var results: [ScanResult] = [SampleData.sampleResult]
    var body: some View {
        List(results, id: \.planSummary) { result in
            NavigationLink(destination: ResultsView(result: result)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Score: \(result.whitenessScore)")
                        Text("Shade: \(result.shade)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("History")
    }
}


