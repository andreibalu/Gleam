import Foundation

enum AchievementID: String, Codable, CaseIterable, Identifiable {
    case streakLegend
    case glowScore
    case scanCollector
    case stainStrategist

    var id: String { rawValue }
}

enum AchievementTier: Int, Codable, Comparable, CaseIterable {
    case locked = 0
    case bronze = 1
    case silver = 2
    case gold = 3

    static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .locked: return "Locked"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }

    var nextTier: AchievementTier? {
        switch self {
        case .locked: return .bronze
        case .bronze: return .silver
        case .silver: return .gold
        case .gold: return nil
        }
    }
}

struct AchievementThresholds: Codable, Equatable {
    let bronze: Double
    let silver: Double
    let gold: Double

    func goal(for tier: AchievementTier) -> Double? {
        switch tier {
        case .bronze: return bronze
        case .silver: return silver
        case .gold: return gold
        case .locked: return nil
        }
    }

    func nextGoal(after tier: AchievementTier) -> Double? {
        guard let nextTier = tier.nextTier else { return nil }
        return goal(for: nextTier)
    }
}

enum AchievementMetric: String, Codable {
    case bestStreak
    case peakScore
    case totalScans
    case stainVariety
}

struct AchievementDefinition: Identifiable, Equatable {
    let id: AchievementID
    let title: String
    let detail: String
    let icon: String
    let lockedIcon: String
    let metric: AchievementMetric
    let thresholds: AchievementThresholds
    let unit: String
    let highlight: String

    static let catalog: [AchievementDefinition] = [
        AchievementDefinition(
            id: .streakLegend,
            title: "Streak Legend",
            detail: "Scan on consecutive days to keep your fire alive.",
            icon: "flame.fill",
            lockedIcon: "flame",
            metric: .bestStreak,
            thresholds: AchievementThresholds(bronze: 3, silver: 7, gold: 14),
            unit: "days",
            highlight: "Daily streak"
        ),
        AchievementDefinition(
            id: .glowScore,
            title: "Glow Score",
            detail: "Lift your peak glow score to elite levels.",
            icon: "sparkles",
            lockedIcon: "sparkles",
            metric: .peakScore,
            thresholds: AchievementThresholds(bronze: 60, silver: 75, gold: 90),
            unit: "pts",
            highlight: "Whiteness score"
        ),
        AchievementDefinition(
            id: .scanCollector,
            title: "Scan Collector",
            detail: "Build a body of work with consistent scans.",
            icon: "camera.badge.clock",
            lockedIcon: "camera",
            metric: .totalScans,
            thresholds: AchievementThresholds(bronze: 5, silver: 15, gold: 40),
            unit: "scans",
            highlight: "Lifetime scans"
        ),
        AchievementDefinition(
            id: .stainStrategist,
            title: "Stain Strategist",
            detail: "Identify the full range of lifestyle stain tags.",
            icon: "drop.triangle.fill",
            lockedIcon: "drop.triangle",
            metric: .stainVariety,
            thresholds: AchievementThresholds(bronze: 2, silver: 4, gold: 6),
            unit: "tags",
            highlight: "Distinct tags"
        )
    ]
}

struct AchievementRecord: Codable, Equatable {
    var id: AchievementID
    var tier: AchievementTier
    var unlockedAt: Date?
}

struct AchievementSnapshot: Identifiable, Equatable {
    let definition: AchievementDefinition
    let tier: AchievementTier
    let progressFraction: Double
    let value: Double
    let nextThreshold: Double?
    let unlockedAt: Date?

    var id: AchievementID { definition.id }

    var isUnlocked: Bool {
        tier != .locked
    }

    var progressLabel: String {
        if tier == .gold {
            return "Legendary"
        }
        if let target = nextThreshold {
            let valueText = Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
            let targetText = Self.numberFormatter.string(from: NSNumber(value: target)) ?? "\(Int(target))"
            return "\(valueText) / \(targetText) \(definition.unit)"
        }
        let valueText = Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(valueText) \(definition.unit)"
    }

    var nextTierLabel: String? {
        tier.nextTier?.label
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

struct AchievementCelebration: Identifiable, Equatable {
    let id = UUID()
    let achievementId: AchievementID
    let tier: AchievementTier
    let title: String
    let detail: String
    let icon: String
}
