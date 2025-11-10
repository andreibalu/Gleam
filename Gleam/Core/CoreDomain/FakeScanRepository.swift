import Foundation

struct FakeScanRepository: ScanRepository {
    func analyze(imageData: Data, tags: [String], previousTakeaways: [String]) async throws -> ScanResult {
        try await Task.sleep(nanoseconds: 200_000_000)
        return SampleData.sampleResult
    }

    func generatePlan(history: [PlanHistoryContext]) async throws -> Recommendations {
        Recommendations(
            immediate: ["Brush for two minutes with whitening paste tonight"],
            daily: ["Floss gently before bed", "Rinse with fluoridated mouthwash"],
            weekly: ["Use gentle whitening strips once this week"],
            caution: ["Skip dark sodas for 48 hours"]
        )
    }

    func fetchLatest() async throws -> ScanResult? {
        SampleData.sampleResult
    }
}


