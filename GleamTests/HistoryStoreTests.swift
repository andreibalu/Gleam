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
        let store = HistoryStore(repository: repository)

        await store.load()
        let itemToDelete = try XCTUnwrap(store.items.first)

        await store.delete(itemToDelete)

        XCTAssertFalse(store.items.contains(itemToDelete))
        XCTAssertEqual(repository.deletedIds, [itemToDelete.id])
    }

    func testAppendAddsNewItemAtTop() async throws {
        let repository = HistoryRepositorySpy(listResult: [])
        let expectedId = "id-123"
        let expectedDate = Date(timeIntervalSince1970: 1_000)
        let store = HistoryStore(
            repository: repository,
            idGenerator: { expectedId },
            dateProvider: { expectedDate }
        )

        let result = SampleData.sampleResult

        await store.load()
        store.append(result)

        XCTAssertEqual(store.items.count, 1)
        let newItem = try XCTUnwrap(store.items.first)
        XCTAssertEqual(newItem.id, expectedId)
        XCTAssertEqual(newItem.createdAt, expectedDate)
        XCTAssertEqual(newItem.result, result)
    }

    private func sampleItems() -> [HistoryItem] {
        let result = SampleData.sampleResult
        return [
            HistoryItem(id: "1", createdAt: Date(timeIntervalSince1970: 100), result: result),
            HistoryItem(id: "2", createdAt: Date(timeIntervalSince1970: 50), result: result)
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
