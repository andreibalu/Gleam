import XCTest
@testable import Gleam

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testLoadPopulatesItemsFromRepository() async throws {
        let expected = sampleItems()
        let repository = HistoryRepositorySpy(listResult: expected)
        let store = HistoryStore(repository: repository)

        await store.load()

        XCTAssertEqual(store.items, expected)
        XCTAssertTrue(repository.listCalled)
    }

    func testDeleteRemovesItemAndCallsRepository() async throws {
        let initial = sampleItems()
        let repository = HistoryRepositorySpy(listResult: initial)
        let remoteDeletionSpy = RemoteDeletionSpy()
        let store = HistoryStore(
            repository: repository,
            remoteDeletionHandler: remoteDeletionSpy.delete
        )

        await store.load()
        let itemToDelete = try XCTUnwrap(store.items.first)

        await store.delete(itemToDelete)

        XCTAssertFalse(store.items.contains(itemToDelete))
        XCTAssertEqual(repository.deletedIds, [itemToDelete.id])
        XCTAssertEqual(remoteDeletionSpy.deletedIds, [itemToDelete.id])
    }

    func testAppendAddsNewItemAtTop() async throws {
        let repository = HistoryRepositorySpy(listResult: [])
        let expectedId = "id-123"
        let expectedDate = Date(timeIntervalSince1970: 1_000)
        let store = HistoryStore(
            repository: repository,
            dateProvider: { expectedDate }
        )

        let outcome = AnalyzeOutcome(
            id: expectedId,
            createdAt: expectedDate,
            result: SampleData.sampleResult,
            contextTags: []
        )

        await store.load()
        store.append(outcome: outcome, imageData: nil, fallbackContextTags: [])

        XCTAssertEqual(store.items.count, 1)
        let newItem = try XCTUnwrap(store.items.first)
        XCTAssertEqual(newItem.id, expectedId)
        XCTAssertEqual(newItem.createdAt, expectedDate)
        XCTAssertEqual(newItem.result, outcome.result)
    }

    func testClearAllResetsItemsAndMetrics() async throws {
        let repository = HistoryRepositorySpy(listResult: sampleItems())
        let store = HistoryStore(repository: repository)
        await store.load()
        XCTAssertFalse(store.items.isEmpty)

        await store.clearAll()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.currentStreak, 0)
        XCTAssertEqual(store.bestStreak, 0)
        XCTAssertEqual(store.metrics, .empty)
    }

    func testMetricsReflectAppendedItems() async throws {
        let repository = HistoryRepositorySpy(listResult: [])
        let store = HistoryStore(repository: repository)
        await store.load()

        let outcome = AnalyzeOutcome(
            id: "m1",
            createdAt: Date(),
            result: SampleData.sampleResult,
            contextTags: ["coffee", "tea"]
        )
        store.append(outcome: outcome, imageData: nil, fallbackContextTags: [])

        XCTAssertEqual(store.metrics.totalScans, 1)
        XCTAssertEqual(store.metrics.highestScore, SampleData.sampleResult.whitenessScore)
        XCTAssertEqual(store.metrics.latestScore, SampleData.sampleResult.whitenessScore)
        XCTAssertEqual(store.metrics.distinctTagCount, 2)
    }

    func testSyncAddsMissingRemoteItems() async throws {
        let repository = HistoryRepositorySpy(listResult: [])
        let store = HistoryStore(repository: repository)
        await store.load()

        let remote = HistoryItem(
            id: "remote-1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            result: SampleData.sampleResult,
            contextTags: []
        )
        await store.sync(with: [remote])

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, "remote-1")
    }

    func testSyncDeduplicatesItemsWithinTwoMinuteWindow() async throws {
        let baseDate = Date(timeIntervalSince1970: 10_000)
        let localItem = HistoryItem(
            id: "local-id",
            createdAt: baseDate,
            result: SampleData.sampleResult,
            contextTags: []
        )
        let repository = HistoryRepositorySpy(listResult: [localItem])
        let store = HistoryStore(repository: repository)
        await store.load()

        // Remote item with same result, within 2-minute window
        let remoteItem = HistoryItem(
            id: "remote-id",
            createdAt: baseDate.addingTimeInterval(60),
            result: SampleData.sampleResult,
            contextTags: []
        )
        await store.sync(with: [remoteItem])

        XCTAssertEqual(store.items.count, 1, "Duplicate within 2-min window should be merged")
        XCTAssertEqual(store.items.first?.id, "remote-id", "Remote ID should win after merge")
    }

    func testSyncDoesNotDeduplicateItemsOutsideTwoMinuteWindow() async throws {
        let baseDate = Date(timeIntervalSince1970: 10_000)
        let localItem = HistoryItem(
            id: "local-id",
            createdAt: baseDate,
            result: SampleData.sampleResult,
            contextTags: []
        )
        let repository = HistoryRepositorySpy(listResult: [localItem])
        let store = HistoryStore(repository: repository)
        await store.load()

        let remoteItem = HistoryItem(
            id: "remote-id",
            createdAt: baseDate.addingTimeInterval(200),
            result: SampleData.sampleResult,
            contextTags: []
        )
        await store.sync(with: [remoteItem])

        XCTAssertEqual(store.items.count, 2, "Items outside 2-min window should both be kept")
    }

    func testCurrentStreakForConsecutiveDays() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: today)!

        let result = SampleData.sampleResult
        let items = [
            HistoryItem(id: "a", createdAt: today, result: result, contextTags: []),
            HistoryItem(id: "b", createdAt: yesterday, result: result, contextTags: []),
            HistoryItem(id: "c", createdAt: dayBefore, result: result, contextTags: [])
        ]
        let repository = HistoryRepositorySpy(listResult: items)
        let store = HistoryStore(repository: repository)
        await store.load()

        XCTAssertEqual(store.currentStreak, 3)
    }

    func testCurrentStreakBreaksOnGap() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let result = SampleData.sampleResult
        let items = [
            HistoryItem(id: "a", createdAt: today, result: result, contextTags: []),
            HistoryItem(id: "b", createdAt: twoDaysAgo, result: result, contextTags: [])
        ]
        let repository = HistoryRepositorySpy(listResult: items)
        let store = HistoryStore(repository: repository)
        await store.load()

        XCTAssertEqual(store.currentStreak, 1, "Gap of 2 days should break the streak")
    }

    private func sampleItems() -> [HistoryItem] {
        let result = SampleData.sampleResult
        return [
            HistoryItem(id: "1", createdAt: Date(timeIntervalSince1970: 100), result: result, contextTags: []),
            HistoryItem(id: "2", createdAt: Date(timeIntervalSince1970: 50), result: result, contextTags: [])
        ]
    }
}

private final class HistoryRepositorySpy: HistoryRepository {
    var listCalled = false
    var listResult: [HistoryItem]
    var deletedIds: [String] = []

    init(listResult: [HistoryItem]) {
        self.listResult = listResult
    }

    func list() async throws -> [HistoryItem] {
        listCalled = true
        return listResult
    }

    func delete(id: String) async throws {
        deletedIds.append(id)
        listResult.removeAll { $0.id == id }
    }
}

private final class RemoteDeletionSpy {
    private(set) var deletedIds: [String] = []

    func delete(id: String) async throws {
        deletedIds.append(id)
    }
}
