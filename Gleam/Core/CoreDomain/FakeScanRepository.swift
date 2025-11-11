import Foundation

struct FakeScanRepository: ScanRepository {
    func analyze(
        imageData: Data,
        tags: [String],
        previousTakeaways: [String],
        recentTagHistory: [[String]]
    ) async throws -> AnalyzeOutcome {
        try await Task.sleep(nanoseconds: 200_000_000)
        return AnalyzeOutcome(
            id: UUID().uuidString,
            createdAt: Date(),
            result: SampleData.sampleResult,
            contextTags: tags
        )
    }

    func fetchLatest() async throws -> ScanResult? {
        SampleData.sampleResult
    }

    func fetchLatestPlan() async throws -> PlanOutcome? {
        let plan = Recommendations(
            immediate: ["Brush for two minutes with whitening paste tonight"],
            daily: ["Floss gently before bed", "Rinse with fluoridated mouthwash"],
            weekly: ["Use gentle whitening strips once this week"],
            caution: ["Skip dark sodas for 48 hours"]
        )
        let status = PlanStatus(
            source: .latestCache,
            isUnchanged: true,
            reason: .latestRequest,
            inputHash: UUID().uuidString,
            updatedAt: Date()
        )
        return PlanOutcome(plan: plan, status: status)
    }

    func fetchHistory(limit: Int) async throws -> [HistoryItem] {
        []
    }

    func deleteHistoryItem(id: String) async throws { }
}


