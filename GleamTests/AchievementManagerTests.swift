import XCTest
@testable import Gleam

@MainActor
final class AchievementManagerTests: XCTestCase {

    // MARK: - Test Doubles

    private final class AchievementPersistingSpy: AchievementPersisting {
        private(set) var savedRecords: [AchievementRecord] = []
        var storedRecords: [AchievementRecord] = []

        func loadAchievementRecords() async -> [AchievementRecord] {
            storedRecords
        }

        func saveAchievementRecords(_ records: [AchievementRecord]) async {
            savedRecords = records
        }
    }

    private final class AuthRepositorySpy: AuthRepository {
        func currentUserId() async -> String? { nil }
        func authToken() async throws -> String? { nil }
        func signInWithGoogle(presentingController: UIViewController) async throws {}
        func signOut() throws {}
        func deleteAccount() async throws {}
    }

    private final class HistoryRepositorySpy: HistoryRepository {
        let listResult: [HistoryItem]
        init(listResult: [HistoryItem]) { self.listResult = listResult }
        func list() async throws -> [HistoryItem] { listResult }
        func delete(id: String) async throws {}
    }

    // MARK: - Helpers

    /// Builds a fully-bootstrapped AchievementManager with the given history items.
    private func makeManager(
        items: [HistoryItem] = [],
        storedRecords: [AchievementRecord] = []
    ) async -> (AchievementManager, AchievementPersistingSpy) {
        let historyStore = HistoryStore(repository: HistoryRepositorySpy(listResult: items))
        await historyStore.load()

        let persistence = AchievementPersistingSpy()
        persistence.storedRecords = storedRecords

        let manager = AchievementManager(
            historyStore: historyStore,
            persistence: persistence,
            authRepository: AuthRepositorySpy()
        )

        // Drain the async bootstrap Task spawned in init.
        // bootstrap() has 3 suspension points (load, evaluate, pullFromCloud), so 5 yields is ample.
        for _ in 0..<5 { await Task.yield() }

        return (manager, persistence)
    }

    private func scanItem(id: String, score: Int = 50, tags: [String] = [], daysAgo: Int = 0) -> HistoryItem {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date()))!
        let result = ScanResult(
            whitenessScore: score,
            shade: "A2",
            detectedIssues: [],
            confidence: 0.9,
            referralNeeded: false,
            disclaimer: nil,
            personalTakeaway: nil
        )
        return HistoryItem(id: id, createdAt: date, result: result, contextTags: tags)
    }

    // MARK: - Initial State

    func testSnapshotCountMatchesCatalogCount() async throws {
        let (manager, _) = await makeManager()
        XCTAssertEqual(manager.snapshots.count, AchievementDefinition.catalog.count)
    }

    func testInitialSnapshotsAreAllLocked() async throws {
        let (manager, _) = await makeManager()
        XCTAssertTrue(manager.snapshots.allSatisfy { $0.tier == .locked })
    }

    func testInitialProgressFractionIsZeroForAllSnapshots() async throws {
        let (manager, _) = await makeManager()
        XCTAssertTrue(manager.snapshots.allSatisfy { $0.progressFraction == 0 })
    }

    func testInitialActiveCelebrationIsNil() async throws {
        let (manager, _) = await makeManager()
        XCTAssertNil(manager.activeCelebration)
    }

    func testInitialUnlockedSnapshotsIsEmpty() async throws {
        let (manager, _) = await makeManager()
        XCTAssertTrue(manager.unlockedSnapshots.isEmpty)
    }

    // MARK: - Streak Legend (metric: bestStreak, bronze=3, silver=7, gold=14)

    func testStreakLegendUnlocksBronzeAfterThreeDayStreak() async throws {
        let items = [
            scanItem(id: "a", daysAgo: 0),
            scanItem(id: "b", daysAgo: 1),
            scanItem(id: "c", daysAgo: 2)
        ]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .streakLegend })
        XCTAssertEqual(snapshot.tier, .bronze)
    }

    func testStreakLegendRemainsLockedWithOnlyTwoDayStreak() async throws {
        let items = [
            scanItem(id: "a", daysAgo: 0),
            scanItem(id: "b", daysAgo: 1)
        ]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .streakLegend })
        XCTAssertEqual(snapshot.tier, .locked)
    }

    // MARK: - Glow Score (metric: peakScore, bronze=60, silver=75, gold=90)

    func testGlowScoreUnlocksBronzeAtSixtyPoints() async throws {
        let items = [scanItem(id: "a", score: 60)]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .glowScore })
        XCTAssertEqual(snapshot.tier, .bronze)
    }

    func testGlowScoreUnlocksSilverAtSeventyFivePoints() async throws {
        let items = [scanItem(id: "a", score: 75)]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .glowScore })
        XCTAssertEqual(snapshot.tier, .silver)
    }

    func testGlowScoreRemainsLockedBelowBronzeThreshold() async throws {
        let items = [scanItem(id: "a", score: 59)]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .glowScore })
        XCTAssertEqual(snapshot.tier, .locked)
    }

    // MARK: - Scan Collector (metric: totalScans, bronze=5, silver=15, gold=40)

    func testScanCollectorUnlocksBronzeAtFiveScans() async throws {
        let items = (1...5).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.tier, .bronze)
    }

    func testScanCollectorUnlocksGoldAtFortyScans() async throws {
        let items = (1...40).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.tier, .gold)
    }

    func testScanCollectorRemainsLockedWithFourScans() async throws {
        let items = (1...4).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.tier, .locked)
    }

    // MARK: - Stain Strategist (metric: stainVariety, bronze=2, silver=4, gold=6)

    func testStainStrategistUnlocksBronzeWithTwoDistinctTags() async throws {
        let items = [
            scanItem(id: "a", tags: ["coffee"]),
            scanItem(id: "b", daysAgo: 1, tags: ["wine"])
        ]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .stainStrategist })
        XCTAssertEqual(snapshot.tier, .bronze)
    }

    func testStainStrategistRemainsLockedWithOneDistinctTag() async throws {
        let items = [
            scanItem(id: "a", tags: ["coffee"]),
            scanItem(id: "b", daysAgo: 1, tags: ["coffee"])
        ]
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .stainStrategist })
        XCTAssertEqual(snapshot.tier, .locked)
    }

    // MARK: - Progress Fraction

    func testProgressFractionIsZeroWithNoScans() async throws {
        let (manager, _) = await makeManager()

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.progressFraction, 0)
    }

    func testProgressFractionIsOneWhenGoldTierReached() async throws {
        let items = (1...40).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.progressFraction, 1.0, accuracy: 0.001)
    }

    func testProgressFractionIsPartialBetweenTiers() async throws {
        // scanCollector: bronze=5, silver=15 → 10 scans → 50% of bronze→silver span
        let items = (1...10).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.progressFraction, 0.5, accuracy: 0.001)
    }

    // MARK: - Celebration

    func testCelebrationIsEnqueuedOnFirstUnlock() async throws {
        // 5 scans → scanCollector bronze unlocks
        let items = (1...5).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        XCTAssertNotNil(manager.activeCelebration)
    }

    func testDismissCelebrationClearsActiveCelebration() async throws {
        let items = (1...5).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        let celebration = try XCTUnwrap(manager.activeCelebration)
        manager.dismissCelebration(celebration)

        XCTAssertNil(manager.activeCelebration)
    }

    func testDismissingWrongCelebrationDoesNotClearActive() async throws {
        let items = (1...5).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        // Create a celebration that was NOT enqueued by the manager (different auto-generated UUID)
        let staleCelebration = AchievementCelebration(
            achievementId: .scanCollector,
            tier: .bronze,
            title: "Old",
            detail: "Old detail",
            icon: "star"
        )
        manager.dismissCelebration(staleCelebration)

        XCTAssertNotNil(manager.activeCelebration, "Dismissing a different celebration should have no effect")
    }

    // MARK: - Persistence

    func testPersistenceIsCalledWhenAchievementUnlocks() async throws {
        let items = (1...5).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (_, spy) = await makeManager(items: items)

        XCTAssertFalse(spy.savedRecords.isEmpty)
    }

    func testNoPersistenceCallWhenNothingUnlocks() async throws {
        let (_, spy) = await makeManager()

        XCTAssertTrue(spy.savedRecords.isEmpty, "No save should happen when no achievement unlocks")
    }

    // MARK: - Stored Records (bootstrap from persistence)

    func testStoredRecordsAreRestoredOnInit() async throws {
        let existingRecord = AchievementRecord(id: .scanCollector, tier: .bronze, unlockedAt: Date())
        let (manager, _) = await makeManager(storedRecords: [existingRecord])

        let snapshot = try XCTUnwrap(manager.snapshots.first { $0.id == .scanCollector })
        XCTAssertEqual(snapshot.tier, .bronze)
    }

    func testUnlockedSnapshotsOnlyIncludesNonLockedTiers() async throws {
        let items = (1...5).map { scanItem(id: "s\($0)", daysAgo: $0) }
        let (manager, _) = await makeManager(items: items)

        XCTAssertTrue(manager.unlockedSnapshots.allSatisfy { $0.tier != .locked })
    }
}
