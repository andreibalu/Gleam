import SwiftUI

/// Tracks the free-tier daily scan limit (3 scans per calendar day).
///
/// Persists via `@AppStorage` so counts survive app restarts.
/// Premium users bypass all limits — always check `subscriptionManager.isPremium` first.
@MainActor
final class ScanLimitManager: ObservableObject {

    static let freeScansPerDay = 3

    // Stored as "yyyy-MM-dd" string; resets count when the date changes
    @AppStorage("scanLimit_date")  private var storedDate:  String = ""
    @AppStorage("scanLimit_count") private var storedCount: Int    = 0

    // MARK: - Published

    @Published private(set) var scansUsedToday: Int = 0

    init() {
        syncFromStorage()
    }

    // MARK: - Public API

    /// How many free scans remain today. Always ≥ 0.
    var freeScansRemaining: Int {
        max(0, Self.freeScansPerDay - scansUsedToday)
    }

    /// Whether a free-tier user can scan right now.
    var canScanAsFreeUser: Bool {
        scansUsedToday < Self.freeScansPerDay
    }

    /// Call after a successful scan to increment the daily counter.
    func recordScan() {
        refreshDateIfNeeded()
        storedCount += 1
        scansUsedToday = storedCount
    }

    // MARK: - Private

    private func syncFromStorage() {
        refreshDateIfNeeded()
        scansUsedToday = storedCount
    }

    /// Resets the counter when the calendar date has changed.
    private func refreshDateIfNeeded() {
        let today = Self.todayString()
        if storedDate != today {
            storedDate  = today
            storedCount = 0
            scansUsedToday = 0
        }
    }

    private static func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
