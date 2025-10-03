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
    @State private var navigationPath: [ScanResult] = []
    @State private var showOnboarding: Bool = false
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $navigationPath) {
                HomeView()
                    .navigationDestination(for: ScanResult.self) { result in
                        ResultsView(result: result)
                    }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                ScanView { result in
                    navigationPath = [result]
                    selectedTab = 0
                }
            }
            .tabItem { Label("Scan", systemImage: "camera") }
            .tag(1)

            NavigationStack {
                HistoryView()
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
            } else if !didCompleteOnboarding {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
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
}

//#Preview {
//    ContentView()
//}
