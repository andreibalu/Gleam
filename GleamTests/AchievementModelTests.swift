import XCTest
@testable import Gleam

@MainActor
final class AchievementModelTests: XCTestCase {

    // MARK: - AchievementTier ordering

    func testTierOrdering() {
        XCTAssertLessThan(AchievementTier.locked, .bronze)
        XCTAssertLessThan(AchievementTier.bronze, .silver)
        XCTAssertLessThan(AchievementTier.silver, .gold)
    }

    func testTierRawValues() {
        XCTAssertEqual(AchievementTier.locked.rawValue, 0)
        XCTAssertEqual(AchievementTier.bronze.rawValue, 1)
        XCTAssertEqual(AchievementTier.silver.rawValue, 2)
        XCTAssertEqual(AchievementTier.gold.rawValue, 3)
    }

    func testNextTierProgression() {
        XCTAssertEqual(AchievementTier.locked.nextTier, .bronze)
        XCTAssertEqual(AchievementTier.bronze.nextTier, .silver)
        XCTAssertEqual(AchievementTier.silver.nextTier, .gold)
        XCTAssertNil(AchievementTier.gold.nextTier)
    }

    // MARK: - AchievementThresholds

    func testThresholdsGoalForTier() {
        let thresholds = AchievementThresholds(bronze: 5, silver: 15, gold: 40)
        XCTAssertEqual(thresholds.goal(for: .bronze), 5)
        XCTAssertEqual(thresholds.goal(for: .silver), 15)
        XCTAssertEqual(thresholds.goal(for: .gold), 40)
        XCTAssertNil(thresholds.goal(for: .locked))
    }

    func testThresholdsNextGoalAfterTier() {
        let thresholds = AchievementThresholds(bronze: 3, silver: 7, gold: 14)
        XCTAssertEqual(thresholds.nextGoal(after: .locked), 3)
        XCTAssertEqual(thresholds.nextGoal(after: .bronze), 7)
        XCTAssertEqual(thresholds.nextGoal(after: .silver), 14)
        XCTAssertNil(thresholds.nextGoal(after: .gold))
    }

    // MARK: - AchievementDefinition catalog

    func testCatalogContainsFourAchievements() {
        XCTAssertEqual(AchievementDefinition.catalog.count, 4)
    }

    func testCatalogContainsAllExpectedIDs() {
        let ids = AchievementDefinition.catalog.map(\.id)
        XCTAssertTrue(ids.contains(.streakLegend))
        XCTAssertTrue(ids.contains(.glowScore))
        XCTAssertTrue(ids.contains(.scanCollector))
        XCTAssertTrue(ids.contains(.stainStrategist))
    }

    func testStreakLegendThresholds() {
        let def = AchievementDefinition.catalog.first { $0.id == .streakLegend }!
        XCTAssertEqual(def.thresholds.bronze, 3)
        XCTAssertEqual(def.thresholds.silver, 7)
        XCTAssertEqual(def.thresholds.gold, 14)
    }

    func testGlowScoreThresholds() {
        let def = AchievementDefinition.catalog.first { $0.id == .glowScore }!
        XCTAssertEqual(def.thresholds.bronze, 60)
        XCTAssertEqual(def.thresholds.silver, 75)
        XCTAssertEqual(def.thresholds.gold, 90)
    }

    func testScanCollectorThresholds() {
        let def = AchievementDefinition.catalog.first { $0.id == .scanCollector }!
        XCTAssertEqual(def.thresholds.bronze, 5)
        XCTAssertEqual(def.thresholds.silver, 15)
        XCTAssertEqual(def.thresholds.gold, 40)
    }

    func testStainStrategistThresholds() {
        let def = AchievementDefinition.catalog.first { $0.id == .stainStrategist }!
        XCTAssertEqual(def.thresholds.bronze, 2)
        XCTAssertEqual(def.thresholds.silver, 4)
        XCTAssertEqual(def.thresholds.gold, 6)
    }

    // MARK: - AchievementSnapshot

    func testSnapshotIsUnlockedWhenTierIsNotLocked() {
        let definition = AchievementDefinition.catalog.first!
        let snapshot = AchievementSnapshot(
            definition: definition,
            tier: .bronze,
            progressFraction: 0.5,
            value: 3,
            nextThreshold: 7,
            unlockedAt: Date()
        )
        XCTAssertTrue(snapshot.isUnlocked)
    }

    func testSnapshotIsLockedWhenTierIsLocked() {
        let definition = AchievementDefinition.catalog.first!
        let snapshot = AchievementSnapshot(
            definition: definition,
            tier: .locked,
            progressFraction: 0,
            value: 0,
            nextThreshold: 3,
            unlockedAt: nil
        )
        XCTAssertFalse(snapshot.isUnlocked)
    }

    func testSnapshotProgressLabelShowsLegendaryForGold() {
        let definition = AchievementDefinition.catalog.first!
        let snapshot = AchievementSnapshot(
            definition: definition,
            tier: .gold,
            progressFraction: 1.0,
            value: 14,
            nextThreshold: nil,
            unlockedAt: Date()
        )
        XCTAssertEqual(snapshot.progressLabel, "Legendary")
    }

    func testSnapshotProgressLabelShowsProgressWhenHasTarget() {
        let def = AchievementDefinition.catalog.first { $0.id == .scanCollector }!
        let snapshot = AchievementSnapshot(
            definition: def,
            tier: .bronze,
            progressFraction: 0.3,
            value: 7,
            nextThreshold: 15,
            unlockedAt: Date()
        )
        XCTAssertTrue(snapshot.progressLabel.contains("7"))
        XCTAssertTrue(snapshot.progressLabel.contains("15"))
        XCTAssertTrue(snapshot.progressLabel.contains("scans"))
    }

    func testNextTierLabelForBronzeIsSilver() {
        let definition = AchievementDefinition.catalog.first!
        let snapshot = AchievementSnapshot(
            definition: definition,
            tier: .bronze,
            progressFraction: 0.5,
            value: 3,
            nextThreshold: 7,
            unlockedAt: Date()
        )
        XCTAssertEqual(snapshot.nextTierLabel, "Silver")
    }

    func testNextTierLabelForGoldIsNil() {
        let definition = AchievementDefinition.catalog.first!
        let snapshot = AchievementSnapshot(
            definition: definition,
            tier: .gold,
            progressFraction: 1.0,
            value: 14,
            nextThreshold: nil,
            unlockedAt: Date()
        )
        XCTAssertNil(snapshot.nextTierLabel)
    }

    // MARK: - AchievementRecord codable

    func testAchievementRecordCodableRoundTrip() throws {
        let record = AchievementRecord(id: .streakLegend, tier: .silver, unlockedAt: Date(timeIntervalSince1970: 1_000))
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(AchievementRecord.self, from: data)
        XCTAssertEqual(record, decoded)
    }
}
