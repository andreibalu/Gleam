import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    private let repository: any HistoryRepository
    private let idGenerator: () -> String
    private let dateProvider: () -> Date
    private let appendHandler: (HistoryItem) -> Void

    init(
        repository: any HistoryRepository,
        idGenerator: @escaping () -> String = { UUID().uuidString },
        dateProvider: @escaping () -> Date = Date.init,
        appendHandler: @escaping (HistoryItem) -> Void = { _ in }
    ) {
        self.repository = repository
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
        self.appendHandler = appendHandler
    }

    func load() async {
        do {
            let fetched = try await repository.list()
            items = fetched.sorted { $0.createdAt > $1.createdAt }
        } catch { }
    }

    func delete(_ item: HistoryItem) async {
        do {
            try await repository.delete(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch { }
    }

    func append(_ result: ScanResult) {
        let newItem = HistoryItem(
            id: idGenerator(),
            createdAt: dateProvider(),
            result: result
        )
        appendHandler(newItem)
        items.insert(newItem, at: 0)
    }
}
