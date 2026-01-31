import Combine
import Foundation

struct ReminderTime: Codable, Equatable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    func formatted(
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            return "--:--"
        }

        let formatter = ReminderTime.formatter
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    func asDate(on referenceDate: Date = Date(), calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? referenceDate
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct BrushingHabitConfiguration: Codable, Equatable {
    var morningReminder: ReminderTime
    var eveningReminder: ReminderTime
}

struct BrushingDayRecord: Codable, Equatable {
    var day: Date
    var morningCompleted: Bool
    var eveningCompleted: Bool

    init(day: Date, morningCompleted: Bool = false, eveningCompleted: Bool = false) {
        self.day = day
        self.morningCompleted = morningCompleted
        self.eveningCompleted = eveningCompleted
    }

    var isComplete: Bool {
        morningCompleted && eveningCompleted
    }

    static func empty(for day: Date) -> BrushingDayRecord {
        BrushingDayRecord(day: day)
    }
}

enum BrushingSlot: String, Codable {
    case morning
    case evening
}

enum BrushingSlotState: Equatable {
    case locked
    case available
    case completed
}

enum BrushingSource {
    case manual
    case flow
}

enum BrushingCompletionResult {
    case recorded
    case alreadyCompleted
    case locked
    case notConfigured
}

struct BrushingCompletionEvent: Identifiable, Equatable {
    let id = UUID()
    let slot: BrushingSlot
    let timestamp: Date
}

struct BrushingHabitSnapshot: Codable {
    var configuration: BrushingHabitConfiguration?
    var records: [String: BrushingDayRecord]
    var bestStreak: Int

    static let empty = BrushingHabitSnapshot(configuration: nil, records: [:], bestStreak: 0)
}

protocol BrushingHabitSnapshotPersisting {
    func loadSnapshot() -> BrushingHabitSnapshot
    func saveSnapshot(_ snapshot: BrushingHabitSnapshot)
}

struct UserDefaultsBrushingHabitPersistence: BrushingHabitSnapshotPersisting {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageKey = "brushing_habit_snapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshot() -> BrushingHabitSnapshot {
        guard let data = defaults.data(forKey: storageKey) else {
            return .empty
        }

        do {
            return try decoder.decode(BrushingHabitSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    func saveSnapshot(_ snapshot: BrushingHabitSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Ignore persistence errors silently
        }
    }
}

@MainActor
final class BrushingHabitStore: ObservableObject {
    @Published private(set) var configuration: BrushingHabitConfiguration?
    @Published private(set) var todayRecord: BrushingDayRecord
    @Published private(set) var currentStreak: Int
    @Published private(set) var bestStreak: Int
    @Published private(set) var lastCompletionEvent: BrushingCompletionEvent?

    var isConfigured: Bool {
        configuration != nil
    }

    var dailyProgress: Double {
        let completed = (todayRecord.morningCompleted ? 1.0 : 0.0) + (todayRecord.eveningCompleted ? 1.0 : 0.0)
        return completed / 2.0
    }

    private var records: [String: BrushingDayRecord]
    private let persistence: any BrushingHabitSnapshotPersisting
    private var calendar: Calendar

    init(
        persistence: any BrushingHabitSnapshotPersisting = UserDefaultsBrushingHabitPersistence(),
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.persistence = persistence
        self.calendar = calendar

        let snapshot = persistence.loadSnapshot()
        self.configuration = snapshot.configuration
        self.records = snapshot.records
        self.bestStreak = snapshot.bestStreak

        let today = calendar.startOfDay(for: now)
        let key = Self.key(for: today, calendar: calendar)
        let record = snapshot.records[key] ?? BrushingDayRecord.empty(for: today)
        self.todayRecord = record
        self.currentStreak = Self.calculateStreak(records: snapshot.records, referenceDate: today, calendar: calendar)
    }

    func configure(morning: ReminderTime, evening: ReminderTime, now: Date = Date()) {
        configuration = BrushingHabitConfiguration(morningReminder: morning, eveningReminder: evening)
        persist(referenceDate: now)
    }

    func reminder(for slot: BrushingSlot) -> ReminderTime? {
        guard let configuration else { return nil }
        switch slot {
        case .morning:
            return configuration.morningReminder
        case .evening:
            return configuration.eveningReminder
        }
    }

    func slotState(for slot: BrushingSlot, at date: Date = Date()) -> BrushingSlotState {
        refreshIfNeeded(date: date)
        switch slot {
        case .morning:
            if todayRecord.morningCompleted { return .completed }
            return isSlotAvailable(slot, at: date) ? .available : .locked
        case .evening:
            if todayRecord.eveningCompleted { return .completed }
            return isSlotAvailable(slot, at: date) ? .available : .locked
        }
    }

    func refreshIfNeeded(date: Date = Date()) {
        let startOfDay = calendar.startOfDay(for: date)
        if calendar.isDate(todayRecord.day, inSameDayAs: startOfDay) {
            return
        }

        let key = Self.key(for: startOfDay, calendar: calendar)
        todayRecord = records[key] ?? BrushingDayRecord.empty(for: startOfDay)
        currentStreak = Self.calculateStreak(records: records, referenceDate: startOfDay, calendar: calendar)
    }

    @discardableResult
    func markBrushed(_ slot: BrushingSlot, date: Date = Date(), source: BrushingSource = .manual) -> BrushingCompletionResult {
        guard isConfigured else { return .notConfigured }

        refreshIfNeeded(date: date)

        if source == .manual {
            guard isSlotAvailable(slot, at: date) else {
                return .locked
            }
        }

        let currentDay = calendar.startOfDay(for: date)
        let key = Self.key(for: currentDay, calendar: calendar)
        var record = records[key] ?? BrushingDayRecord.empty(for: currentDay)

        switch slot {
        case .morning:
            guard !record.morningCompleted else { return .alreadyCompleted }
            record.morningCompleted = true
        case .evening:
            guard !record.eveningCompleted else { return .alreadyCompleted }
            record.eveningCompleted = true
        }

        record.day = currentDay
        todayRecord = record
        records[key] = record

        recalculateStreaks(referenceDate: date)
        lastCompletionEvent = BrushingCompletionEvent(slot: slot, timestamp: date)
        persist(referenceDate: date)
        return .recorded
    }

    private func isSlotAvailable(_ slot: BrushingSlot, at date: Date) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch slot {
        case .morning:
            // Morning available from 4 AM to 3 PM
            return hour >= 4 && hour < 15
        case .evening:
            // Evening available from 3 PM to 4 AM (next day)
            // Effectively 15:00 - 24:00 and 00:00 - 04:00
            return hour >= 15 || hour < 4
        }
    }

    private func recalculateStreaks(referenceDate: Date) {
        let startOfDay = calendar.startOfDay(for: referenceDate)
        currentStreak = Self.calculateStreak(records: records, referenceDate: startOfDay, calendar: calendar)
        if currentStreak > bestStreak {
            bestStreak = currentStreak
        }
    }

    private func persist(referenceDate: Date) {
        pruneRecords(referenceDate: referenceDate)
        let snapshot = BrushingHabitSnapshot(configuration: configuration, records: records, bestStreak: bestStreak)
        persistence.saveSnapshot(snapshot)
    }

    private func pruneRecords(referenceDate: Date) {
        let threshold = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: referenceDate)) ?? .distantPast
        records = records.filter { _, record in
            record.day >= threshold
        }
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func calculateStreak(
        records: [String: BrushingDayRecord],
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: referenceDate)

        while true {
            let key = key(for: cursor, calendar: calendar)
            guard let record = records[key], record.isComplete else { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }
}

