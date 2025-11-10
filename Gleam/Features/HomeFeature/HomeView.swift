import SwiftUI

struct HomeView: View {
    @Environment(\.scanRepository) private var scanRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var isScanning = false
    @State private var lastResult: ScanResult? = nil
    @State private var showCamera = false
    @State private var animateScore = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                VStack(spacing: AppSpacing.s) {
                    Text("Gleam")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("Track your smile journey")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, AppSpacing.m)

                // Main Score Circle
                if let result = lastResult {
                    VStack(spacing: AppSpacing.l) {
                        AnimatedScoreCircle(
                            score: normalizedScore(result.whitenessScore),
                            animate: animateScore
                        )
                        .frame(height: 240)
                        .padding(.horizontal, AppSpacing.m)
                        
                        // Motivational message
                        MotivationalMessage(score: normalizedScore(result.whitenessScore))
                            .padding(.horizontal, AppSpacing.m)
                    }
                } else {
                    // Empty state
                    VStack(spacing: AppSpacing.m) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.secondary)
                                Text("Start Your\nJourney")
                                    .font(.title3.bold())
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal, AppSpacing.m)
                    }
                }

                // Stats Row: Streak & Best Streak
                HStack(spacing: AppSpacing.m) {
                    StatCard(
                        icon: "flame.fill",
                        iconColor: historyStore.currentStreak > 0 ? .orange : .gray,
                        title: "Current Streak",
                        value: "\(historyStore.currentStreak)",
                        subtitle: historyStore.currentStreak == 1 ? "day" : "days",
                        animate: historyStore.currentStreak > 0
                    )
                    
                    StatCard(
                        icon: "trophy.fill",
                        iconColor: .yellow,
                        title: "Best Streak",
                        value: "\(historyStore.bestStreak)",
                        subtitle: historyStore.bestStreak == 1 ? "day" : "days",
                        animate: false
                    )
                }
                .padding(.horizontal, AppSpacing.m)

                // Scan Button
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                        Text("Scan Your Smile")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .buttonStyle(GamifiedButtonStyle())
                .accessibilityIdentifier("home_scan_button")
                .padding(.horizontal, AppSpacing.m)
                
                // Progress Insight
                if let result = lastResult {
                    ProgressInsight(result: result)
                        .padding(.horizontal, AppSpacing.m)
                }
            }
            .padding(.vertical, AppSpacing.m)
        }
        .background(AppColors.background.ignoresSafeArea())
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { data in
                scanSession.capturedImageData = data
                showCamera = false
            }
            .accessibilityIdentifier("camera_sheet")
            .ignoresSafeArea()
        }
        .task {
            do { lastResult = try await scanRepository.fetchLatest() } catch { }
        }
        .onChange(of: scanSession.shouldOpenCamera) { _, shouldOpen in
            if shouldOpen {
                showCamera = true
                scanSession.shouldOpenCamera = false
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                animateScore = true
            }
        }
    }
    
    private func normalizedScore(_ rawScore: Int) -> Double {
        // Convert 0-100 to 0-10 scale
        return Double(rawScore) / 10.0
    }
}

// MARK: - Animated Score Circle
private struct AnimatedScoreCircle: View {
    let score: Double // 0-10 scale
    let animate: Bool
    
    @State private var displayedScore: Double = 0
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 24)
            
            // Animated progress circle
            Circle()
                .trim(from: 0, to: animate ? min(1.0, displayedScore / 10.0) : 0)
                .stroke(
                    scoreGradient,
                    style: StrokeStyle(lineWidth: 24, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.2, dampingFraction: 0.6), value: displayedScore)
            
            // Center content
            VStack(spacing: 4) {
                Text(String(format: "%.1f", displayedScore))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreGradient)
                    .contentTransition(.numericText(value: displayedScore))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: displayedScore)
                
                Text("/ 10")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Text(scoreLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(scoreLabelColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(scoreLabelColor.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.top, 8)
            }
            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
        }
        .onChange(of: animate) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
                    displayedScore = score
                }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .onAppear {
            if animate {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3)) {
                    displayedScore = score
                }
            }
        }
    }
    
    private var scoreGradient: LinearGradient {
        let colors: [Color]
        if displayedScore >= 8.0 {
            colors = [.green, .mint]
        } else if displayedScore >= 6.0 {
            colors = [.blue, .cyan]
        } else if displayedScore >= 4.0 {
            colors = [.orange, .yellow]
        } else {
            colors = [.red, .orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var scoreLabel: String {
        if displayedScore >= 9.0 { return "✨ Brilliant" }
        if displayedScore >= 8.0 { return "🌟 Excellent" }
        if displayedScore >= 7.0 { return "🎯 Great" }
        if displayedScore >= 6.0 { return "👍 Good" }
        if displayedScore >= 5.0 { return "📈 Improving" }
        if displayedScore >= 3.0 { return "💪 Keep Going" }
        return "🚀 Start Here"
    }
    
    private var scoreLabelColor: Color {
        if displayedScore >= 8.0 { return .green }
        if displayedScore >= 6.0 { return .blue }
        if displayedScore >= 4.0 { return .orange }
        return .red
    }
}

// MARK: - Stat Card
private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    let animate: Bool
    
    @State private var flameAnimation = false
    
    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(iconColor)
                .scaleEffect(flameAnimation ? 1.2 : 1.0)
                .animation(
                    animate ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
                    value: flameAnimation
                )
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.m)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .shadow(color: iconColor.opacity(animate ? 0.3 : 0), radius: 10, x: 0, y: 5)
        .onAppear {
            if animate {
                flameAnimation = true
            }
        }
    }
}

// MARK: - Motivational Message
private struct MotivationalMessage: View {
    let score: Double
    
    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(tip)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
    
    private var message: String {
        if score >= 9.0 { return "🎉 Outstanding! Your smile is brilliant!" }
        if score >= 8.0 { return "🌟 Excellent work! Keep it up!" }
        if score >= 7.0 { return "🎯 Great progress! You're doing well!" }
        if score >= 6.0 { return "👍 Good job! Keep improving!" }
        if score >= 5.0 { return "📈 You're on the right track!" }
        if score >= 3.0 { return "💪 Keep going! Progress takes time!" }
        return "🚀 Let's start your journey!"
    }
    
    private var tip: String {
        if score >= 9.0 { return "Maintain your routine for lasting results" }
        if score >= 8.0 { return "You're almost perfect! Stay consistent" }
        if score >= 7.0 { return "Small improvements lead to big results" }
        if score >= 6.0 { return "Focus on daily care for better results" }
        if score >= 5.0 { return "Consistency is key to improvement" }
        if score >= 3.0 { return "Follow your daily recommendations" }
        return "Start with small, daily habits"
    }
}

// MARK: - Progress Insight
private struct ProgressInsight: View {
    let result: ScanResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                Text("Latest Scan")
                    .font(.headline)
                Spacer()
                Text(shadeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if !result.detectedIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Focus Areas")
                        .font(.subheadline.weight(.medium))
                    ForEach(result.detectedIssues.prefix(3), id: \.key) { issue in
                        HStack {
                            Circle()
                                .fill(severityColor(issue.severity))
                                .frame(width: 8, height: 8)
                            Text(issue.key.capitalized)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
    
    private var shadeDescription: String {
        // Simplified shade description
        let shadeMap: [String: String] = [
            "A1": "Very Light", "A2": "Light", "A3": "Medium-Light",
            "B1": "Light", "B2": "Medium-Light", "B3": "Medium",
            "C1": "Light", "C2": "Medium", "C3": "Medium-Dark",
            "D2": "Medium", "D3": "Medium-Dark", "D4": "Dark"
        ]
        return shadeMap[result.shade] ?? result.shade
    }
    
    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .yellow
        }
    }
}



