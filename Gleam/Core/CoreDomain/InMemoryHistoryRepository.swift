import Foundation

final class InMemoryHistoryRepository: HistoryRepository {
    private var storage: [HistoryItem]

    init(initialItems: [HistoryItem] = []) {
        self.storage = initialItems
    }

    func list() async throws -> [HistoryItem] {
        storage
    }

    func delete(id: String) async throws {
        storage.removeAll { $0.id == id }
    }

    func insert(_ item: HistoryItem) {
        storage.insert(item, at: 0)
    }
}
