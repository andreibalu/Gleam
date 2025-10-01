import Foundation

struct FakeScanRepository: ScanRepository {
    func analyze(imageData: Data) async throws -> ScanResult {
        try await Task.sleep(nanoseconds: 200_000_000)
        return SampleData.sampleResult
    }

    func fetchLatest() async throws -> ScanResult? {
        SampleData.sampleResult
    }
}


