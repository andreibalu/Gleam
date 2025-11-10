import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var bestStreak: Int = 0

    private let repository: any HistoryRepository
    private let imageStorage = LocalImageStorage()
    private let idGenerator: () -> String
    private let dateProvider: () -> Date
    private let appendHandler: (HistoryItem) -> Void
    private var didResetForUITests = false

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
            if ProcessInfo.processInfo.arguments.contains("--uitest-skip-onboarding"),
               !didResetForUITests,
               let persistentRepository = repository as? PersistentHistoryRepository {
                await persistentRepository.resetAll()
                items = []
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
            try await repository.delete(id: item.id)
            // Delete associated image
            await imageStorage.deleteImage(for: item.id)
            items.removeAll { $0.id == item.id }
        } catch { }
    }

    func append(_ result: ScanResult, imageData: Data?) {
        let newItem = HistoryItem(
            id: idGenerator(),
            createdAt: dateProvider(),
            result: result
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
    
    func loadImage(for historyItemId: String) async -> Data? {
        await imageStorage.loadImage(for: historyItemId)
    }
    
    private func calculateStreaks() {
        guard !items.isEmpty else {
            currentStreak = 0
            bestStreak = 0
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
    }
}
