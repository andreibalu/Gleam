//
//  ContentView.swift
//  Gleam
//
//  Created by andrei on 01.10.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Int = 0
    @State private var navigationPath: [ScanResult] = []
    @State private var showOnboarding: Bool = false
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $navigationPath) {
                HomeView {
                    selectedTab = 1
                }
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
            if !didCompleteOnboarding { showOnboarding = true }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}

//#Preview {
//    ContentView()
//}
