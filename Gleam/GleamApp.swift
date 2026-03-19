//
//  GleamApp.swift
//  Gleam
//
//  Created by andrei on 01.10.2025.
//

import SwiftUI
import SwiftData
import FirebaseCore
import StoreKit
import UIKit

@main
struct GleamApp: App {
    @AppStorage(AppTheme.storageKey) private var themeRawValue: String = AppTheme.system.rawValue
    @StateObject private var scanSession: ScanSession
    @StateObject private var historyStore: HistoryStore
    @StateObject private var achievementManager: AchievementManager
    @StateObject private var brushingHabitStore: BrushingHabitStore
    @StateObject private var subscriptionManager: SubscriptionManager
    @StateObject private var scanLimitManager: ScanLimitManager
    private let authRepository: any AuthRepository
    private let scanRepository: any ScanRepository

    init() {
        // Minimal initialization for tests - avoid creating complex StateObjects
        if Self.isRunningTests {
            self.authRepository = NoopAuthRepository()
            self.scanRepository = NoopScanRepository()
            // Create minimal dummy objects for tests - they won't be used
            let noopPersistence = NoopAchievementPersistence()
            let historyStore = HistoryStore(repository: noopPersistence)
            self._scanSession = StateObject(wrappedValue: ScanSession())
            self._historyStore = StateObject(wrappedValue: historyStore)
            self._achievementManager = StateObject(wrappedValue: AchievementManager(
                historyStore: historyStore,
                persistence: noopPersistence,
                authRepository: NoopAuthRepository()
            ))
            self._brushingHabitStore = StateObject(wrappedValue: BrushingHabitStore(persistence: NoopBrushingPersistence()))
            self._subscriptionManager = StateObject(wrappedValue: SubscriptionManager())
            self._scanLimitManager = StateObject(wrappedValue: ScanLimitManager())
        } else {
            Self.configureFirebase()
            AppTheme.migrateLegacySettingIfNeeded()
            let historyRepository = PersistentHistoryRepository()
            let authRepository: any AuthRepository = FirebaseAuthRepository()
            self.authRepository = authRepository
            let scanRepository: any ScanRepository = RemoteScanRepository(
                httpClient: DefaultHTTPClient(),
                authRepository: authRepository
            )
            self.scanRepository = scanRepository
            let store = HistoryStore(
                repository: historyRepository,
                appendHandler: { item in
                    Task { await historyRepository.insert(item) }
                },
                remoteDeletionHandler: { id in
                    try await scanRepository.deleteHistoryItem(id: id)
                }
            )
            self._scanSession = StateObject(wrappedValue: ScanSession())
            self._historyStore = StateObject(wrappedValue: store)
            self._achievementManager = StateObject(wrappedValue: AchievementManager(
                historyStore: store,
                persistence: historyRepository,
                authRepository: authRepository
            ))
            self._brushingHabitStore = StateObject(wrappedValue: BrushingHabitStore())
            self._subscriptionManager = StateObject(wrappedValue: SubscriptionManager())
            self._scanLimitManager = StateObject(wrappedValue: ScanLimitManager())
        }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: Self.isRunningTests)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                EmptyView()
            } else {
                ContentView()
                    .preferredColorScheme(selectedTheme.colorScheme)
                    .scanRepository(scanRepository)
                    .authRepository(authRepository)
                    .environmentObject(scanSession)
                    .environmentObject(historyStore)
                    .environmentObject(achievementManager)
                    .environmentObject(brushingHabitStore)
                    .environmentObject(subscriptionManager)
                    .environmentObject(scanLimitManager)
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private static func configureFirebase() {
        guard FirebaseApp.app() == nil else { return }
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
        } else {
            print("[Gleam] GoogleService-Info.plist missing. Firebase not configured.")
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct NoopScanRepository: ScanRepository {
    func analyze(
        imageData: Data,
        tags: [String],
        previousTakeaways: [String],
        recentTagHistory: [[String]]
    ) async throws -> AnalyzeOutcome {
        throw AppError.unknown
    }

    func fetchLatest() async throws -> ScanResult? { nil }
    func fetchLatestPlan() async throws -> PlanOutcome? { nil }
    func fetchHistory(limit: Int) async throws -> [HistoryItem] { [] }
    func deleteHistoryItem(id: String) async throws {}
}

private final class NoopAuthRepository: AuthRepository {
    func currentUserId() async -> String? { nil }
    func authToken() async throws -> String? { nil }
    func signInWithGoogle(presentingController: UIViewController) async throws {}
    func signOut() throws {}
    func deleteAccount() async throws {}
}

private struct NoopBrushingPersistence: BrushingHabitSnapshotPersisting {
    func loadSnapshot() -> BrushingHabitSnapshot { .empty }
    func saveSnapshot(_ snapshot: BrushingHabitSnapshot) {}
}

private final class NoopAchievementPersistence: HistoryRepository, AchievementPersisting {
    func list() async throws -> [HistoryItem] { [] }
    func delete(id: String) async throws {}
    func loadAchievementRecords() async -> [AchievementRecord] { [] }
    func saveAchievementRecords(_ records: [AchievementRecord]) async {}
}
