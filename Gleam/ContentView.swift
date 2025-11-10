//
//  ContentView.swift
//  Gleam
//
//  Created by andrei on 01.10.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var selectedTab: Int = 0
    @State private var homeNavigationPath: [ScanResult] = []
    @State private var historyNavigationPath: [ScanResult] = []
    @State private var showOnboarding: Bool = false
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homeNavigationPath) {
                HomeView()
                    .navigationDestination(for: ScanResult.self) { result in
                        ResultsView(result: result)
                    }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                ScanView { result in
                    // Navigate to History tab and show the result
                    historyNavigationPath = [result]
                    selectedTab = 2
                }
            }
            .tabItem { Label("Scan", systemImage: "camera") }
            .tag(1)

            NavigationStack(path: $historyNavigationPath) {
                HistoryView()
                    .navigationDestination(for: ScanResult.self) { result in
                        // Find the history item ID for this result
                        ResultsView(result: result, historyItemId: findHistoryItemId(for: result))
                    }
            }
            .tabItem { Label("History", systemImage: "clock") }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--uitest-skip-onboarding") {
                didCompleteOnboarding = true
                showOnboarding = false
            } else {
                showOnboarding = !didCompleteOnboarding
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onChange(of: didCompleteOnboarding) { _, completed in
            if completed {
                showOnboarding = false
            } else {
                scanSession.reset()
                showOnboarding = true
            }
        }
        .onChange(of: scanSession.shouldOpenCamera) { _, shouldOpen in
            if shouldOpen {
                selectedTab = 0
            }
        }
        .onChange(of: scanSession.capturedImageData) { _, data in
            if data != nil {
                selectedTab = 1
            }
        }
    }
    
    private func findHistoryItemId(for result: ScanResult) -> String? {
        // Find the history item that matches this result
        return historyStore.items.first { $0.result == result }?.id
    }
}

//#Preview {
//    ContentView()
//}
