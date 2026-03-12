import XCTest
import UIKit
@testable import Gleam

@MainActor
final class RemoteScanRepositoryTests: XCTestCase {

    // MARK: - parseDate

    func testParseDateWithFractionalSeconds() {
        let result = RemoteScanRepository.parseDate("2024-01-15T10:30:00.000Z")
        XCTAssertNotNil(result)
    }

    func testParseDateWithoutFractionalSeconds() {
        let result = RemoteScanRepository.parseDate("2024-01-15T10:30:00Z")
        XCTAssertNotNil(result)
    }

    func testParseDateReturnsNilForInvalidString() {
        let result = RemoteScanRepository.parseDate("not-a-date")
        XCTAssertNil(result)
    }

    func testParseDateFractionalAndPlainProduceSameTimestamp() {
        let withFractional = RemoteScanRepository.parseDate("2024-06-01T08:00:00.000Z")
        let withoutFractional = RemoteScanRepository.parseDate("2024-06-01T08:00:00Z")
        XCTAssertEqual(withFractional, withoutFractional)
    }

    // MARK: - analyze – validation

    func testAnalyzeThrowsInvalidImageForEmptyData() async {
        let (repo, _, _) = makeRepository()
        do {
            _ = try await repo.analyze(imageData: Data(), tags: [], previousTakeaways: [], recentTagHistory: [])
            XCTFail("Expected .invalidImage error")
        } catch let error as AppError {
            XCTAssertEqual(error, .invalidImage)
        }
    }

    // MARK: - analyze – success mapping

    func testAnalyzeMapsResponseToAnalyzeOutcome() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = analyzeResponseJSON(id: "scan-123", whitenessScore: 75, contextTags: ["coffee"])

        let outcome = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])

        XCTAssertEqual(outcome.id, "scan-123")
        XCTAssertEqual(outcome.result.whitenessScore, 75)
        XCTAssertEqual(outcome.contextTags, ["coffee"])
    }

    func testAnalyzeFallsBackToUUIDWhenIdMissing() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = analyzeResponseJSON(id: nil, whitenessScore: 70, contextTags: nil)

        let outcome = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])

        XCTAssertFalse(outcome.id.isEmpty)
    }

    func testAnalyzeFallsBackToEmptyTagsWhenContextTagsMissing() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = analyzeResponseJSON(id: "id", whitenessScore: 70, contextTags: nil)

        let outcome = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])

        XCTAssertEqual(outcome.contextTags, [])
    }

    // MARK: - analyze – error mapping

    func testAnalyzeMaps401ToUnauthorized() async {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.requestFailed(401)
        do {
            _ = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testAnalyzeMaps403ToUnauthorized() async {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.requestFailed(403)
        do {
            _ = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testAnalyzeMapsDecodingErrorToDecoding() async {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.decoding
        do {
            _ = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error, .decoding)
        }
    }

    func testAnalyzeMapsURLErrorToNetwork() async {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        do {
            _ = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error, .network)
        }
    }

    // MARK: - analyze – headers

    func testAnalyzeIncludesBearerTokenWhenAvailable() async throws {
        let (repo, httpSpy, authSpy) = makeRepository()
        authSpy.stubbedToken = "my-token"
        httpSpy.stubbedData = analyzeResponseJSON(id: "id", whitenessScore: 70, contextTags: nil)

        _ = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])

        XCTAssertEqual(httpSpy.lastHeaders["Authorization"], "Bearer my-token")
    }

    func testAnalyzeSendsEmptyHeadersWhenNoToken() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = analyzeResponseJSON(id: "id", whitenessScore: 70, contextTags: nil)

        _ = try await repo.analyze(imageData: Data([0xFF]), tags: [], previousTakeaways: [], recentTagHistory: [])

        XCTAssertNil(httpSpy.lastHeaders["Authorization"])
    }

    // MARK: - fetchLatest

    func testFetchLatestReturnsNilOn404() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.requestFailed(404)

        let result = try await repo.fetchLatest()

        XCTAssertNil(result)
    }

    func testFetchLatestReturnsScanResultOn200() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = analyzeResponseJSON(id: "id", whitenessScore: 80, contextTags: nil)

        let result = try await repo.fetchLatest()

        XCTAssertEqual(result?.whitenessScore, 80)
    }

    func testFetchLatestMaps401ToUnauthorized() async {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.requestFailed(401)
        do {
            _ = try await repo.fetchLatest()
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    // MARK: - fetchLatestPlan

    func testFetchLatestPlanReturnsNilOn404() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.requestFailed(404)

        let result = try await repo.fetchLatestPlan()

        XCTAssertNil(result)
    }

    func testFetchLatestPlanReturnsPlanOn200() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = planResponseJSON(source: "openai", unchanged: false)

        let outcome = try await repo.fetchLatestPlan()

        XCTAssertNotNil(outcome)
        XCTAssertEqual(outcome?.plan.daily, ["Brush twice a day"])
    }

    func testFetchLatestPlanMapsMetaSourceToStatus() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = planResponseJSON(source: "openai", unchanged: false)

        let outcome = try await repo.fetchLatestPlan()

        XCTAssertEqual(outcome?.status?.source, .openai)
        XCTAssertEqual(outcome?.status?.isUnchanged, false)
    }

    func testFetchLatestPlanStatusIsNilForUnknownSource() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = planResponseJSON(source: "unknown-source", unchanged: false)

        let outcome = try await repo.fetchLatestPlan()

        XCTAssertNotNil(outcome)
        XCTAssertNil(outcome?.status)
    }

    // MARK: - fetchHistory

    func testFetchHistoryReturnsEmptyArrayOn404() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedError = APIError.requestFailed(404)

        let items = try await repo.fetchHistory(limit: 10)

        XCTAssertEqual(items, [])
    }

    func testFetchHistoryReturnsMappedItemsOn200() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = historyListResponseJSON()

        let items = try await repo.fetchHistory(limit: 10)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "history-item-1")
        XCTAssertEqual(items.first?.result.whitenessScore, 70)
    }

    func testFetchHistoryPassesLimitAsQueryParameter() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = historyListResponseJSON(items: [])

        _ = try await repo.fetchHistory(limit: 25)

        let urlComponents = URLComponents(url: try XCTUnwrap(httpSpy.lastURL), resolvingAgainstBaseURL: false)
        let limitItem = urlComponents?.queryItems?.first { $0.name == "limit" }
        XCTAssertEqual(limitItem?.value, "25")
    }

    // MARK: - deleteHistoryItem

    func testDeleteHistoryItemSendsDeleteMethod() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = try JSONSerialization.data(withJSONObject: ["success": true])

        try await repo.deleteHistoryItem(id: "item-to-delete")

        XCTAssertEqual(httpSpy.lastMethod, "DELETE")
    }

    func testDeleteHistoryItemSendsCorrectIdInBody() async throws {
        let (repo, httpSpy, _) = makeRepository()
        httpSpy.stubbedData = try JSONSerialization.data(withJSONObject: ["success": true])

        try await repo.deleteHistoryItem(id: "item-to-delete")

        let body = try XCTUnwrap(httpSpy.lastBodyData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "item-to-delete")
    }

    // MARK: - Helpers

    private func makeRepository() -> (RemoteScanRepository, HTTPClientSpy, AuthRepositorySpy) {
        let httpSpy = HTTPClientSpy()
        let authSpy = AuthRepositorySpy()
        let repo = RemoteScanRepository(httpClient: httpSpy, authRepository: authSpy)
        return (repo, httpSpy, authSpy)
    }

    private func analyzeResponseJSON(id: String?, whitenessScore: Int, contextTags: [String]?) -> Data {
        var dict: [String: Any] = [
            "result": [
                "whitenessScore": whitenessScore,
                "shade": "B1",
                "confidence": 0.9
            ]
        ]
        if let id { dict["id"] = id }
        if let tags = contextTags { dict["contextTags"] = tags }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func planResponseJSON(source: String, unchanged: Bool) -> Data {
        let dict: [String: Any] = [
            "plan": [
                "immediate": [],
                "daily": ["Brush twice a day"],
                "weekly": [],
                "caution": []
            ],
            "meta": [
                "source": source,
                "unchanged": unchanged
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    private func historyListResponseJSON(items: [[String: Any]]? = nil) -> Data {
        let defaultItems: [[String: Any]] = [[
            "id": "history-item-1",
            "result": [
                "whitenessScore": 70,
                "shade": "B1",
                "confidence": 0.9
            ],
            "contextTags": [],
            "createdAt": "2024-01-01T12:00:00Z"
        ]]
        let dict: [String: Any] = ["items": items ?? defaultItems]
        return try! JSONSerialization.data(withJSONObject: dict)
    }
}

// MARK: - Test Doubles

private final class HTTPClientSpy: HTTPClient {
    var stubbedData: Data = Data()
    var stubbedError: Error?
    private(set) var lastURL: URL?
    private(set) var lastMethod: String?
    private(set) var lastHeaders: [String: String] = [:]
    private(set) var lastBodyData: Data?

    func send<RequestBody: Encodable, ResponseBody: Decodable>(
        url: URL,
        method: String,
        headers: [String: String],
        body: RequestBody?
    ) async throws -> ResponseBody {
        lastURL = url
        lastMethod = method
        lastHeaders = headers
        if let body { lastBodyData = try? JSONEncoder().encode(body) }
        if let error = stubbedError { throw error }
        return try JSONDecoder().decode(ResponseBody.self, from: stubbedData)
    }
}

private final class AuthRepositorySpy: AuthRepository {
    var stubbedToken: String?

    func currentUserId() async -> String? { nil }
    func authToken() async throws -> String? { stubbedToken }
    func signInWithGoogle(presentingController: UIViewController) async throws {}
    func signOut() throws {}
    func deleteAccount() async throws {}
}
