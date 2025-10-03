//
//  GleamApp.swift
//  Gleam
//
//  Created by andrei on 01.10.2025.
//

import SwiftUI
import SwiftData
import PhotosUI

@main
struct GleamApp: App {
    @StateObject private var scanSession = ScanSession()
    @StateObject private var historyStore: HistoryStore

    init() {
        let historyRepository = PersistentHistoryRepository()
        _historyStore = StateObject(wrappedValue: HistoryStore(
            repository: historyRepository,
            appendHandler: { item in
                Task { await historyRepository.insert(item) }
            }
        ))
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
                .scanRepository(RemoteScanRepository(httpClient: DefaultHTTPClient()))
                .environmentObject(scanSession)
                .environmentObject(historyStore)
        }
        .modelContainer(sharedModelContainer)
    }
}
