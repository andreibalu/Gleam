import XCTest
@testable import Gleam

@MainActor
final class PersistentHistoryRepositoryTests: XCTestCase {
    private var tempDirectory: URL!
    private var storageURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        tempDirectory = base
        storageURL = base.appendingPathComponent("history.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        storageURL = nil
        try super.tearDownWithError()
    }

    func testInsertPersistsItemsAcrossInstances() async throws {
        let repository = PersistentHistoryRepository(fileURL: storageURL)
        let item = HistoryItem(id: UUID().uuidString, createdAt: Date(), result: SampleData.sampleResult, contextTags: [])

        await repository.insert(item)

        let stored = try await repository.list()
        XCTAssertEqual(stored, [item])

        let secondRepository = PersistentHistoryRepository(fileURL: storageURL)
        let restored = try await secondRepository.list()
        XCTAssertEqual(restored, [item])
    }

    func testDeleteRemovesPersistedItems() async throws {
        let repository = PersistentHistoryRepository(fileURL: storageURL)
        let first = HistoryItem(id: UUID().uuidString, createdAt: Date(), result: SampleData.sampleResult, contextTags: [])
        let second = HistoryItem(id: UUID().uuidString, createdAt: Date().addingTimeInterval(10), result: SampleData.sampleResult, contextTags: [])

        await repository.insert(first)
        await repository.insert(second)

        try await repository.delete(id: first.id)

        let remaining = try await repository.list()
        XCTAssertEqual(remaining, [second])

        let rehydrated = PersistentHistoryRepository(fileURL: storageURL)
        let persisted = try await rehydrated.list()
        XCTAssertEqual(persisted, [second])
    }
}
