//
//  GleamApp.swift
//  Gleam
//
//  Created by andrei on 01.10.2025.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct GleamApp: App {
    @StateObject private var scanSession = ScanSession()
    @StateObject private var historyStore: HistoryStore
    @StateObject private var achievementManager: AchievementManager
    @StateObject private var brushingHabitStore: BrushingHabitStore
    private let authRepository: any AuthRepository
    private let scanRepository: any ScanRepository

    init() {
        Self.configureFirebase()
        let historyRepository = PersistentHistoryRepository()
        let authRepository = FirebaseAuthRepository()
        self.authRepository = authRepository
        let remoteScanRepository = RemoteScanRepository(
            httpClient: DefaultHTTPClient(),
            authRepository: authRepository
        )
        self.scanRepository = remoteScanRepository
        let store = HistoryStore(
            repository: historyRepository,
            appendHandler: { item in
                Task { await historyRepository.insert(item) }
            },
            remoteDeletionHandler: { id in
                try await remoteScanRepository.deleteHistoryItem(id: id)
            }
        )
        _historyStore = StateObject(wrappedValue: store)
        _achievementManager = StateObject(wrappedValue: AchievementManager(
            historyStore: store,
            persistence: historyRepository,
            authRepository: authRepository
        ))
        _brushingHabitStore = StateObject(wrappedValue: BrushingHabitStore())
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .scanRepository(scanRepository)
                .authRepository(authRepository)
                .environmentObject(scanSession)
                .environmentObject(historyStore)
                .environmentObject(achievementManager)
                .environmentObject(brushingHabitStore)
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
}
