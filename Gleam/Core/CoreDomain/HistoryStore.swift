import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var metrics: HistoryMetrics = .empty

    private let repository: any HistoryRepository
    private let imageStorage = LocalImageStorage()
    private let idGenerator: () -> String
    private let dateProvider: () -> Date
    private let appendHandler: (HistoryItem) -> Void
    private let remoteDeletionHandler: (String) async throws -> Void
    private var didResetForUITests = false

    init(
        repository: any HistoryRepository,
        idGenerator: @escaping () -> String = { UUID().uuidString },
        dateProvider: @escaping () -> Date = Date.init,
        appendHandler: @escaping (HistoryItem) -> Void = { _ in },
        remoteDeletionHandler: @escaping (String) async throws -> Void = { _ in }
    ) {
        self.repository = repository
        self.idGenerator = idGenerator
        self.dateProvider = dateProvider
        self.appendHandler = appendHandler
        self.remoteDeletionHandler = remoteDeletionHandler
    }

    func load() async {
        do {
            if ProcessInfo.processInfo.arguments.contains("--uitest-skip-onboarding"),
               !didResetForUITests,
               let persistentRepository = repository as? PersistentHistoryRepository {
                await persistentRepository.resetAll()
                items = []
                metrics = .empty
                didResetForUITests = true
            } else {
                let fetched = try await repository.list()
                items = fetched.sorted { $0.createdAt > $1.createdAt }
                calculateStreaks()
            }
        } catch { }
    }

    func delete(_ item: HistoryItem) async {
        do {
            try await remoteDeletionHandler(item.id)
        } catch {
            print("⚠️ Failed to delete remote history item: \(error)")
        }

        do {
            try await repository.delete(id: item.id)
        } catch { }

        await imageStorage.deleteImage(for: item.id)
        items.removeAll { $0.id == item.id }
        calculateStreaks()
    }

    func append(outcome: AnalyzeOutcome, imageData: Data?, fallbackContextTags: [String]) {
        let identifier = outcome.id.isEmpty ? idGenerator() : outcome.id
        let contextTags = outcome.contextTags.isEmpty ? fallbackContextTags : outcome.contextTags
        let newItem = HistoryItem(
            id: identifier,
            createdAt: outcome.createdAt,
            result: outcome.result,
            contextTags: contextTags
        )
        
        // Save image locally if provided
        if let imageData = imageData {
            Task {
                do {
                    try await imageStorage.saveImage(imageData, for: newItem.id)
                } catch {
                    // Silently fail - image storage is optional
                }
            }
        }
        
        appendHandler(newItem)
        items.insert(newItem, at: 0)
        calculateStreaks()
    }
    
    func sync(with remoteItems: [HistoryItem]) async {
        // Merge remote history without discarding local items (to preserve local photos).
        // A remote item is considered a duplicate of a local one if:
        // - ScanResult matches AND createdAt is within a short window (2 minutes).
        // This keeps local IDs (used for photo filenames) intact.
        let mergeWindow: TimeInterval = 120
        let localCount = items.count
        let remoteCount = remoteItems.count
        var merged = items
        var duplicatesFound = 0
        
        // Helper to decide if two items represent the same scan event
        func isSameScan(_ a: HistoryItem, _ b: HistoryItem) -> Bool {
            let timeDelta = abs(a.createdAt.timeIntervalSince(b.createdAt))
            return a.result == b.result && timeDelta <= mergeWindow
        }
        
        for remote in remoteItems {
            if let existingIndex = merged.firstIndex(where: { isSameScan($0, remote) }) {
                let existingItem = merged[existingIndex]
                if existingItem.id != remote.id {
                    await imageStorage.moveImage(from: existingItem.id, to: remote.id)
                }
                merged[existingIndex] = HistoryItem(
                    id: remote.id,
                    createdAt: remote.createdAt,
                    result: remote.result,
                    contextTags: remote.contextTags
                )
                duplicatesFound += 1
                continue
            }
            // Otherwise, add the remote entry (it won't have a local photo, which is expected)
            merged.append(remote)
        }
        
        // Sort newest first for UI
        merged.sort { $0.createdAt > $1.createdAt }
        items = merged
        calculateStreaks()
        
        // Log merge stats for observability
        print("📊 History sync: local=\(localCount), remote=\(remoteCount), duplicates=\(duplicatesFound), final=\(merged.count)")
        
        // Persist merged set locally so it survives app restarts
        if let persistent = repository as? PersistentHistoryRepository {
            await persistent.replaceAll(with: merged)
        }
    }
    
    func loadImage(for historyItemId: String) async -> Data? {
        await imageStorage.loadImage(for: historyItemId)
    }

    func clearAll() async {
        items.removeAll()
        currentStreak = 0
        bestStreak = 0
        metrics = .empty
        if let persistent = repository as? PersistentHistoryRepository {
            await persistent.resetAll()
        }
    }

    private func calculateStreaks() {
        guard !items.isEmpty else {
            currentStreak = 0
            bestStreak = 0
            metrics = .empty
            return
        }
        
        let calendar = Calendar.current
        let sortedItems = items.sorted { $0.createdAt > $1.createdAt }
        
        // Calculate current streak
        var streak = 0
        var lastDate: Date? = nil
        let today = calendar.startOfDay(for: dateProvider())
        
        for item in sortedItems {
            let itemDay = calendar.startOfDay(for: item.createdAt)
            
            if lastDate == nil {
                // First item - check if it's today or yesterday
                let daysDiff = calendar.dateComponents([.day], from: itemDay, to: today).day ?? 0
                if daysDiff <= 1 {
                    streak = 1
                    lastDate = itemDay
                } else {
                    break
                }
            } else if let previous = lastDate {
                let daysDiff = calendar.dateComponents([.day], from: itemDay, to: previous).day ?? 0
                if daysDiff == 1 {
                    // Consecutive day
                    streak += 1
                    lastDate = itemDay
                } else if daysDiff == 0 {
                    // Same day, continue
                    continue
                } else {
                    // Gap in streak
                    break
                }
            }
        }
        
        currentStreak = streak
        
        // Calculate best streak
        var tempBestStreak = 0
        var tempCurrentStreak = 0
        var previousDay: Date? = nil
        
        for item in sortedItems.reversed() {
            let itemDay = calendar.startOfDay(for: item.createdAt)
            
            if let previous = previousDay {
                let daysDiff = calendar.dateComponents([.day], from: previous, to: itemDay).day ?? 0
                if daysDiff == 1 {
                    tempCurrentStreak += 1
                } else if daysDiff == 0 {
                    continue
                } else {
                    tempBestStreak = max(tempBestStreak, tempCurrentStreak)
                    tempCurrentStreak = 1
                }
            } else {
                tempCurrentStreak = 1
            }
            previousDay = itemDay
        }
        tempBestStreak = max(tempBestStreak, tempCurrentStreak)
        bestStreak = max(tempBestStreak, currentStreak)
        updateMetrics()
    }

    private func updateMetrics() {
        let highestScore = items.map(\.result.whitenessScore).max() ?? 0
        let distinctTags = Set(items.flatMap(\.contextTags))
        let latestScore = items.first?.result.whitenessScore
        metrics = HistoryMetrics(
            totalScans: items.count,
            highestScore: highestScore,
            distinctTags: distinctTags,
            latestScore: latestScore
        )
    }
}

struct HistoryMetrics: Equatable {
    let totalScans: Int
    let highestScore: Int
    let distinctTags: Set<String>
    let latestScore: Int?

    var distinctTagCount: Int {
        distinctTags.count
    }

    static let empty = HistoryMetrics(
        totalScans: 0,
        highestScore: 0,
        distinctTags: [],
        latestScore: nil
    )
}
