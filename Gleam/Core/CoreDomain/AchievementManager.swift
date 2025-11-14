import Combine
import Foundation
import UIKit
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

protocol AchievementPersisting: AnyObject {
    func loadAchievementRecords() async -> [AchievementRecord]
    func saveAchievementRecords(_ records: [AchievementRecord]) async
}

@MainActor
final class AchievementManager: ObservableObject {
    @Published private(set) var snapshots: [AchievementSnapshot]
    @Published private(set) var activeCelebration: AchievementCelebration?

    private let historyStore: HistoryStore
    private let persistence: AchievementPersisting
    private let authRepository: any AuthRepository
    private var cancellables: Set<AnyCancellable> = []
    private var records: [AchievementID: AchievementRecord] = [:]
    private var pendingCelebrations: [AchievementCelebration] = []
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let upgradeGenerator = UIImpactFeedbackGenerator(style: .heavy)
#if canImport(FirebaseFirestore)
    private let firestore = Firestore.firestore()
#endif

    init(historyStore: HistoryStore, persistence: AchievementPersisting, authRepository: any AuthRepository) {
        self.historyStore = historyStore
        self.persistence = persistence
        self.authRepository = authRepository
        self.snapshots = AchievementDefinition.catalog.map { definition in
            AchievementSnapshot(
                definition: definition,
                tier: .locked,
                progressFraction: 0,
                value: 0,
                nextThreshold: definition.thresholds.goal(for: .bronze),
                unlockedAt: nil
            )
        }

        bindHistory()
        Task { await bootstrap() }
    }

    var unlockedSnapshots: [AchievementSnapshot] {
        snapshots.filter { $0.isUnlocked }
    }

    func dismissCelebration(_ celebration: AchievementCelebration) {
        guard celebration.id == activeCelebration?.id else { return }
        if pendingCelebrations.isEmpty {
            activeCelebration = nil
        } else {
            activeCelebration = pendingCelebrations.removeFirst()
        }
    }

    private func bindHistory() {
        historyStore.$items
            .combineLatest(historyStore.$metrics)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                Task { await self.evaluate(skipHaptics: false) }
            }
            .store(in: &cancellables)
    }

    private func bootstrap() async {
        let stored = await persistence.loadAchievementRecords()
        records = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        await evaluate(skipHaptics: true, shouldSyncCloud: false)
        await pullAchievementsFromCloud()
    }

    private func evaluate(skipHaptics: Bool, shouldSyncCloud: Bool = true) async {
        let context = AchievementContext(
            currentStreak: historyStore.currentStreak,
            bestStreak: historyStore.bestStreak,
            totalScans: historyStore.metrics.totalScans,
            highestScore: historyStore.metrics.highestScore,
            distinctTags: historyStore.metrics.distinctTagCount
        )

        if !skipHaptics {
            notificationGenerator.prepare()
            upgradeGenerator.prepare()
        }

        var updatedRecords = records
        var updatedSnapshots: [AchievementSnapshot] = []
        var newCelebrations: [AchievementCelebration] = []
        var didChange = false

        for definition in AchievementDefinition.catalog {
            let value = metricValue(for: definition.metric, context: context)
            var record = updatedRecords[definition.id] ?? AchievementRecord(id: definition.id, tier: .locked, unlockedAt: nil)
            let previousTier = record.tier
            let achievedTier = tier(for: value, thresholds: definition.thresholds)

            if achievedTier.rawValue > previousTier.rawValue {
                record.tier = achievedTier
                record.unlockedAt = Date()
                updatedRecords[definition.id] = record
                didChange = true

                if !skipHaptics {
                    if previousTier == .locked {
                        notificationGenerator.notificationOccurred(.success)
                    } else {
                        upgradeGenerator.impactOccurred(intensity: 1.0)
                    }
                }

                newCelebrations.append(
                    AchievementCelebration(
                        achievementId: definition.id,
                        tier: achievedTier,
                        title: definition.title,
                        detail: celebrationDetail(for: definition, tier: achievedTier),
                        icon: definition.icon
                    )
                )
            } else {
                updatedRecords[definition.id] = record
            }

            let snapshot = AchievementSnapshot(
                definition: definition,
                tier: record.tier,
                progressFraction: progressFraction(for: value, thresholds: definition.thresholds, tier: record.tier),
                value: value,
                nextThreshold: definition.thresholds.nextGoal(after: record.tier),
                unlockedAt: record.unlockedAt
            )
            updatedSnapshots.append(snapshot)
        }

        records = updatedRecords
        snapshots = updatedSnapshots

        enqueueCelebrations(newCelebrations)

        if didChange {
            await persistence.saveAchievementRecords(updatedRecords.values.sorted { $0.id.rawValue < $1.id.rawValue })
            if shouldSyncCloud {
                await syncAchievementsToCloud(records: Array(updatedRecords.values))
            }
        }
    }

    private func enqueueCelebrations(_ celebrations: [AchievementCelebration]) {
        guard !celebrations.isEmpty else { return }
        if activeCelebration == nil {
            activeCelebration = celebrations.first
            pendingCelebrations = Array(celebrations.dropFirst())
        } else {
            pendingCelebrations.append(contentsOf: celebrations)
        }
    }

    private func metricValue(for metric: AchievementMetric, context: AchievementContext) -> Double {
        switch metric {
        case .bestStreak:
            return Double(max(context.currentStreak, context.bestStreak))
        case .peakScore:
            return Double(context.highestScore)
        case .totalScans:
            return Double(context.totalScans)
        case .stainVariety:
            return Double(context.distinctTags)
        }
    }

    private func tier(for value: Double, thresholds: AchievementThresholds) -> AchievementTier {
        if value >= thresholds.gold {
            return .gold
        } else if value >= thresholds.silver {
            return .silver
        } else if value >= thresholds.bronze {
            return .bronze
        } else {
            return .locked
        }
    }

    private func progressFraction(for value: Double, thresholds: AchievementThresholds, tier: AchievementTier) -> Double {
        if tier == .gold {
            return 1.0
        }

        let lowerBound = thresholds.goal(for: tier) ?? 0
        guard let upperBound = thresholds.nextGoal(after: tier) else {
            return min(1.0, value / max(thresholds.gold, 1))
        }
        let span = max(upperBound - lowerBound, 0.01)
        let normalized = (value - lowerBound) / span
        return min(max(normalized, 0), 1)
    }

    private func celebrationDetail(for definition: AchievementDefinition, tier: AchievementTier) -> String {
        guard let goal = definition.thresholds.goal(for: tier) else {
            return definition.detail
        }
        let goalValue = Int(goal)
        switch tier {
        case .bronze:
            return "Bronze unlocked at \(goalValue) \(definition.unit)."
        case .silver:
            return "Silver reached at \(goalValue) \(definition.unit)."
        case .gold:
            return "Gold achieved with \(goalValue) \(definition.unit)."
        case .locked:
            return definition.detail
        }
    }

    private func pullAchievementsFromCloud() async {
#if canImport(FirebaseFirestore)
        guard let userId = await authRepository.currentUserId(), !userId.isEmpty else { return }
        let collection = firestore.collection("users").document(userId).collection("achievements")

        do {
            let documents = try await withCheckedThrowingContinuation { continuation in
                collection.getDocuments { querySnapshot, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: querySnapshot?.documents ?? [])
                    }
                }
            }

            var updated = records
            documents.forEach { document in
                guard let achievementId = AchievementID(rawValue: document.documentID) else { return }
                let data = document.data()
                let rawTier = data["tier"] as? Int ?? 0
                let tier = AchievementTier(rawValue: rawTier) ?? .locked
                let unlockedAt = (data["unlockedAt"] as? Timestamp)?.dateValue()
                updated[achievementId] = AchievementRecord(id: achievementId, tier: tier, unlockedAt: unlockedAt)
            }

            records = updated
            await persistence.saveAchievementRecords(updated.values.sorted { $0.id.rawValue < $1.id.rawValue })
            await evaluate(skipHaptics: true, shouldSyncCloud: false)
        } catch {
            // Silent failure; achievements will remain local
        }
#endif
    }

    private func syncAchievementsToCloud(records: [AchievementRecord]) async {
#if canImport(FirebaseFirestore)
        guard let userId = await authRepository.currentUserId(), !userId.isEmpty else { return }
        let collection = firestore.collection("users").document(userId).collection("achievements")
        for record in records {
            var payload: [String: Any] = [
                "tier": record.tier.rawValue,
                "updatedAt": Timestamp(date: Date())
            ]
            if let unlockedAt = record.unlockedAt {
                payload["unlockedAt"] = Timestamp(date: unlockedAt)
            }

            _ = try? await withCheckedThrowingContinuation { continuation in
                collection.document(record.id.rawValue).setData(payload, merge: true) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
#endif
    }
}

private struct AchievementContext {
    let currentStreak: Int
    let bestStreak: Int
    let totalScans: Int
    let highestScore: Int
    let distinctTags: Int
}

