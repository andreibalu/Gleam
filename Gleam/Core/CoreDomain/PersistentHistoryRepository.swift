import Foundation

actor PersistentHistoryRepository: HistoryRepository {
    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var storage: [HistoryItem]

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let resolvedURL = fileURL ?? Self.resolveDefaultURL(with: fileManager)

        self.fileManager = fileManager
        self.storageURL = resolvedURL
        self.encoder = encoder
        self.decoder = decoder
        self.storage = Self.loadInitialStorage(from: resolvedURL, decoder: decoder, fileManager: fileManager)
    }

    func list() async throws -> [HistoryItem] {
        storage
    }

    func delete(id: String) async throws {
        storage.removeAll { $0.id == id }
        try persistStorage()
    }

    func insert(_ item: HistoryItem) {
        storage.insert(item, at: 0)
        try? persistStorage()
    }

    func replaceAll(with items: [HistoryItem]) {
        storage = items
        try? persistStorage()
    }

    func resetAll() {
        storage.removeAll()
        if fileManager.fileExists(atPath: storageURL.path) {
            try? fileManager.removeItem(at: storageURL)
        }
    }

    private func persistStorage() throws {
        let directory = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        let data = try encoder.encode(storage)
        try data.write(to: storageURL, options: .atomic)
    }

    private static func loadInitialStorage(from url: URL, decoder: JSONDecoder, fileManager: FileManager) -> [HistoryItem] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([HistoryItem].self, from: data)
        } catch {
            return []
        }
    }

    private static func resolveDefaultURL(with fileManager: FileManager) -> URL {
        let baseDirectory: URL
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseDirectory = url
        } else if let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            baseDirectory = url
        } else {
            baseDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        return baseDirectory.appendingPathComponent("history.json", isDirectory: false)
    }
}
