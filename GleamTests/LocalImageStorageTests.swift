import XCTest
@testable import Gleam

final class LocalImageStorageTests: XCTestCase {

    private var storage: LocalImageStorage!
    private var usedIds: [String] = []

    override func setUp() async throws {
        storage = LocalImageStorage()
        usedIds = []
    }

    override func tearDown() async throws {
        for id in usedIds {
            await storage.deleteImage(for: id)
        }
    }

    private func newId() -> String {
        let id = "test-\(UUID().uuidString)"
        usedIds.append(id)
        return id
    }

    // MARK: - Save & Load

    func testSaveAndLoadRoundTrip() async throws {
        let id = newId()
        let data = Data("fake-jpeg-data".utf8)

        try await storage.saveImage(data, for: id)
        let loaded = await storage.loadImage(for: id)

        XCTAssertEqual(loaded, data)
    }

    func testLoadReturnsNilForUnknownId() async {
        let loaded = await storage.loadImage(for: "nonexistent-\(UUID().uuidString)")
        XCTAssertNil(loaded)
    }

    func testSaveOverwritesExistingImageForSameId() async throws {
        let id = newId()
        let original = Data("original".utf8)
        let updated = Data("updated".utf8)

        try await storage.saveImage(original, for: id)
        try await storage.saveImage(updated, for: id)
        let loaded = await storage.loadImage(for: id)

        XCTAssertEqual(loaded, updated)
    }

    // MARK: - Delete

    func testDeleteRemovesImage() async throws {
        let id = newId()
        try await storage.saveImage(Data("data".utf8), for: id)

        await storage.deleteImage(for: id)
        let loaded = await storage.loadImage(for: id)

        XCTAssertNil(loaded)
    }

    func testDeleteNonexistentImageDoesNotThrow() async {
        // Should silently succeed without crashing
        await storage.deleteImage(for: "nonexistent-\(UUID().uuidString)")
    }

    // MARK: - Move

    func testMoveImageTransfersDataToNewId() async throws {
        let sourceId = newId()
        let destId = newId()
        let data = Data("image-bytes".utf8)

        try await storage.saveImage(data, for: sourceId)
        await storage.moveImage(from: sourceId, to: destId)

        let destData = await storage.loadImage(for: destId)
        XCTAssertEqual(destData, data)
    }

    func testMoveImageRemovesSourceId() async throws {
        let sourceId = newId()
        let destId = newId()

        try await storage.saveImage(Data("bytes".utf8), for: sourceId)
        await storage.moveImage(from: sourceId, to: destId)

        let sourceData = await storage.loadImage(for: sourceId)
        XCTAssertNil(sourceData)
    }

    func testMoveFromNonexistentSourceIsNoOp() async {
        let destId = newId()
        // Should not crash or create a file at destId
        await storage.moveImage(from: "ghost-\(UUID().uuidString)", to: destId)

        let destData = await storage.loadImage(for: destId)
        XCTAssertNil(destData)
    }
}
