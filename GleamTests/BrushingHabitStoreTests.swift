import XCTest
@testable import Gleam

@MainActor
final class BrushingHabitStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore(
        now: Date = Date(),
        persistence: InMemoryBrushingPersistence = InMemoryBrushingPersistence(),
        calendar: Calendar = .current
    ) -> BrushingHabitStore {
        BrushingHabitStore(persistence: persistence, calendar: calendar, now: now)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func morning() -> ReminderTime { ReminderTime(hour: 7, minute: 30) }
    private func evening() -> ReminderTime { ReminderTime(hour: 21, minute: 0) }

    // MARK: - Configuration

    func testUnconfiguredStoreIsNotConfigured() {
        let store = makeStore()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.configuration)
    }

    func testConfigureSetsConfigurationAndPersists() {
        let persistence = InMemoryBrushingPersistence()
        let store = makeStore(persistence: persistence)

        store.configure(morning: morning(), evening: evening())

        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.configuration?.morningReminder, morning())
        XCTAssertEqual(store.configuration?.eveningReminder, evening())
        XCTAssertNotNil(persistence.snapshot.configuration)
    }

    // MARK: - Slot availability

    func testMorningSlotAvailableAt7AM() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let sevenAM = date(hour: 7)
        XCTAssertEqual(store.slotState(for: .morning, at: sevenAM), .available)
    }

    func testMorningSlotAvailableAt2PM() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let twoPM = date(hour: 14)
        XCTAssertEqual(store.slotState(for: .morning, at: twoPM), .available)
    }

    func testMorningSlotLockedAt3PM() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let threePM = date(hour: 15)
        XCTAssertEqual(store.slotState(for: .morning, at: threePM), .locked)
    }

    func testEveningSlotAvailableAt8PM() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let eightPM = date(hour: 20)
        XCTAssertEqual(store.slotState(for: .evening, at: eightPM), .available)
    }

    func testEveningSlotLockedAt10AM() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let tenAM = date(hour: 10)
        XCTAssertEqual(store.slotState(for: .evening, at: tenAM), .locked)
    }

    // MARK: - markBrushed

    func testMarkBrushedReturnsNotConfiguredWhenUnconfigured() {
        let store = makeStore()
        let eightPM = date(hour: 20)
        let result = store.markBrushed(.evening, date: eightPM)
        XCTAssertEqual(result, .notConfigured)
    }

    func testMarkBrushedMorningRecordsCompletion() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let eightAM = date(hour: 8)

        let result = store.markBrushed(.morning, date: eightAM)

        XCTAssertEqual(result, .recorded)
        XCTAssertTrue(store.todayRecord.morningCompleted)
    }

    func testMarkBrushedEveningRecordsCompletion() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let nineOPM = date(hour: 21)

        let result = store.markBrushed(.evening, date: nineOPM)

        XCTAssertEqual(result, .recorded)
        XCTAssertTrue(store.todayRecord.eveningCompleted)
    }

    func testMarkBrushedReturnAlreadyCompletedOnSecondCall() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let eightAM = date(hour: 8)

        store.markBrushed(.morning, date: eightAM)
        let second = store.markBrushed(.morning, date: eightAM)

        XCTAssertEqual(second, .alreadyCompleted)
    }

    func testMarkBrushedReturnsLockedWhenSlotUnavailable() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let threePM = date(hour: 15)

        let result = store.markBrushed(.morning, date: threePM)

        XCTAssertEqual(result, .locked)
    }

    func testMarkBrushedFromFlowBypassesTimelock() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        let threePM = date(hour: 15)

        let result = store.markBrushed(.morning, date: threePM, source: .flow)

        XCTAssertEqual(result, .recorded)
        XCTAssertTrue(store.todayRecord.morningCompleted)
    }

    // MARK: - Daily progress

    func testDailyProgressIsZeroWhenNothingCompleted() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        XCTAssertEqual(store.dailyProgress, 0.0)
    }

    func testDailyProgressIsHalfWhenOneSlotCompleted() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        store.markBrushed(.morning, date: date(hour: 8), source: .flow)
        XCTAssertEqual(store.dailyProgress, 0.5)
    }

    func testDailyProgressIsFullWhenBothCompleted() {
        let store = makeStore()
        store.configure(morning: morning(), evening: evening())
        store.markBrushed(.morning, date: date(hour: 8), source: .flow)
        store.markBrushed(.evening, date: date(hour: 21), source: .flow)
        XCTAssertEqual(store.dailyProgress, 1.0)
    }

    // MARK: - Streaks

    func testStreakIsOneAfterCompletingToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())
        let persistence = InMemoryBrushingPersistence()
        let store = BrushingHabitStore(persistence: persistence, calendar: calendar, now: today)

        store.configure(morning: morning(), evening: evening())
        store.markBrushed(.morning, date: date(hour: 8), source: .flow)
        store.markBrushed(.evening, date: date(hour: 21), source: .flow)

        XCTAssertEqual(store.currentStreak, 1)
    }

    func testBestStreakUpdatesWhenCurrentStreakExceedsIt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())
        let persistence = InMemoryBrushingPersistence()
        let store = BrushingHabitStore(persistence: persistence, calendar: calendar, now: today)

        store.configure(morning: morning(), evening: evening())
        store.markBrushed(.morning, date: date(hour: 8), source: .flow)
        store.markBrushed(.evening, date: date(hour: 21), source: .flow)

        XCTAssertGreaterThanOrEqual(store.bestStreak, store.currentStreak)
    }

    // MARK: - Persistence

    func testSnapshotIsPersistedAfterMarkBrushed() {
        let persistence = InMemoryBrushingPersistence()
        let store = makeStore(persistence: persistence)
        store.configure(morning: morning(), evening: evening())
        store.markBrushed(.morning, date: date(hour: 8), source: .flow)

        XCTAssertNotNil(persistence.snapshot.configuration)
        let savedRecords = persistence.snapshot.records
        XCTAssertFalse(savedRecords.isEmpty)
    }
}

// MARK: - Test Double

private final class InMemoryBrushingPersistence: BrushingHabitSnapshotPersisting {
    var snapshot: BrushingHabitSnapshot = .empty

    func loadSnapshot() -> BrushingHabitSnapshot { snapshot }
    func saveSnapshot(_ s: BrushingHabitSnapshot) { snapshot = s }
}
