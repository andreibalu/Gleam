import SwiftUI

struct HomeView: View {
    @Environment(\.scanRepository) private var scanRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @AppStorage("userFirstName") private var userFirstName: String = "Andrei"
    @State private var lastResult: ScanResult?
    @State private var showCamera = false
    @State private var showPlanSheet = false
    @State private var personalizedPlan: PlanOutcome?
    @State private var hasSyncedCloudState = false

    private let shadeStages = ShadeStage.defaults
    private let defaultPlan = Recommendations(
        immediate: [
            "Brush with whitening toothpaste tonight",
            "Rinse with water after dark drinks",
            "Floss gently before bed"
        ],
        daily: [
            "Use an electric toothbrush each morning",
            "Swish a fluoride mouthwash before sleep"
        ],
        weekly: [
            "Apply gentle whitening strips once",
            "Polish with a soft whitening pen"
        ],
        caution: [
            "Skip dark sodas for 48 hours",
            "Limit coffee to one cup before noon"
        ]
    )

    private var currentPlan: Recommendations {
        personalizedPlan?.plan ?? defaultPlan
    }

    private var hasPersonalizedPlan: Bool {
        guard let status = personalizedPlan?.status else { return false }
        if let planAvailable = status.planAvailable {
            return planAvailable
        }
        if status.source == .default {
            return false
        }
        return true
    }

    private var planStatus: PlanStatus? {
        personalizedPlan?.status
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppSpacing.l) {
                HomeHeroCard(
                    greeting: greetingText,
                    emoji: greetingEmoji,
                    userName: userDisplayName,
                    score: displayScore,
                    stage: stage(for: displayScore ?? 0),
                    nextStage: nextStage(after: displayScore ?? 0),
                    deltaToNext: deltaToNextStage,
                    hasScan: lastResult != nil,
                    onScan: { showCamera = true }
                )

                JourneyProgressSection(
                    score: displayScore,
                    stages: shadeStages,
                    nextStage: nextStage(after: displayScore ?? 0)
                )

                DailyChallengeCard(
                    isCompletedToday: hasScanToday,
                    message: challengeMessage,
                    onScan: { showCamera = true },
                    onCompare: { scanSession.shouldOpenHistory = true },
                    latestResult: lastResult
                )

                PlanPreviewCard(
                    plan: currentPlan,
                    isPersonalized: hasPersonalizedPlan,
                    status: planStatus,
                    onTap: { showPlanSheet = true }
                )

                if let result = lastResult {
                    LatestInsightsCard(result: result)
                }

                AchievementsSection(achievements: achievements)

                LearnAndImproveSection(cards: learnCards)
            }
            .padding(.vertical, AppSpacing.l)
            .padding(.horizontal, AppSpacing.m)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground),
                    Color(.systemBackground).opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { data in
                scanSession.capturedImageData = data
                showCamera = false
            }
            .accessibilityIdentifier("camera_sheet")
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPlanSheet) {
            PlanSheetView(
                plan: currentPlan,
                baselinePlan: defaultPlan,
                status: planStatus,
                isPersonalized: hasPersonalizedPlan
            )
            .presentationDetents([.medium, .large])
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: scanSession.shouldOpenCamera) { _, shouldOpen in
            if shouldOpen {
                showCamera = true
                scanSession.shouldOpenCamera = false
            }
        }
        .onChange(of: historyStore.items) { previousItems, newItems in
            if let latest = newItems.first?.result {
                lastResult = latest
            }
            if newItems.count > previousItems.count {
                Task {
                    await loadLatestPlan()
                }
            }
        }
        .onAppear {
            if lastResult == nil, let latest = historyStore.items.first?.result {
                lastResult = latest
            }
        }
    }

    private func loadLatestResult() async {
        do {
            let latest = try await scanRepository.fetchLatest()
            await MainActor.run {
                lastResult = latest
            }
        } catch {
            // The experience still works without a cached score
        }
    }

    private func loadInitialData() async {
        await loadLatestResult()
        let shouldSync = await MainActor.run { markCloudSyncStarted() }
        guard shouldSync else { return }
        async let historyTask: Void = syncHistoryFromCloud()
        async let planTask: Void = loadLatestPlan()
        _ = await (historyTask, planTask)
    }

    @MainActor
    private func markCloudSyncStarted() -> Bool {
        if hasSyncedCloudState { return false }
        hasSyncedCloudState = true
        return true
    }

    private func syncHistoryFromCloud() async {
        do {
            let remoteItems = try await scanRepository.fetchHistory(limit: 40)
            await historyStore.sync(with: remoteItems)
            if let latest = remoteItems.first?.result {
                await MainActor.run {
                    lastResult = latest
                }
            }
        } catch {
            // Ignore sync errors; local history still works
        }
    }

    private func loadLatestPlan() async {
        do {
            if let plan = try await scanRepository.fetchLatestPlan() {
                await MainActor.run {
                    personalizedPlan = plan
                }
            } else {
                await MainActor.run {
                    personalizedPlan = nil
                }
            }
        } catch {
            // Ignore fetch errors; experience still works with cached plan
        }
    }

    private var displayScore: Double? {
        guard let result = lastResult else { return nil }
        return normalizedScore(result.whitenessScore)
    }

    private var deltaToNextStage: Double? {
        guard let score = displayScore, let next = nextStage(after: score) else { return nil }
        return max(0, next.threshold - score)
    }

    private func normalizedScore(_ rawScore: Int) -> Double {
        Double(rawScore) / 10.0
    }

    private var hasScanToday: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return historyStore.items.contains { item in
            calendar.isDate(calendar.startOfDay(for: item.createdAt), inSameDayAs: today)
        }
    }

    private func stage(for score: Double) -> ShadeStage {
        var current = shadeStages.first ?? ShadeStage.defaults[0]
        for stage in shadeStages {
            if score >= stage.threshold {
                current = stage
            } else {
                break
            }
        }
        return current
    }

    private func nextStage(after score: Double) -> ShadeStage? {
        shadeStages.first { stage in
            stage.threshold > score
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private var greetingEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "☀️"
        case 12..<17: return "🌤"
        case 17..<22: return "🌙"
        default: return "😴"
        }
    }

    private var userDisplayName: String {
        let trimmed = userFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "friend" }
        return trimmed.capitalized
    }

    private var challengeMessage: String {
        if historyStore.currentStreak > 0 {
            return "Scan your smile before 10 PM to extend your streak 🔥"
        } else {
            return "Take your first scan today and start your streak ✨"
        }
    }

    private var achievements: [Achievement] {
        [
            Achievement(emoji: "🔥", title: "1-Day Streak", isUnlocked: historyStore.currentStreak >= 1),
            Achievement(emoji: "🦷", title: "First Scan", isUnlocked: lastResult != nil),
            Achievement(emoji: "🌈", title: "Color Upgrade", isUnlocked: (displayScore ?? 0) >= 6.0),
            Achievement(emoji: "📈", title: "Consistency Rise", isUnlocked: historyStore.items.count >= 3),
            Achievement(emoji: "👑", title: "Consistency King", isUnlocked: historyStore.bestStreak >= 7),
            Achievement(emoji: "🍯", title: "Self-Care Pro", isUnlocked: historyStore.items.count >= 5)
        ]
    }

    private var learnCards: [LearnCard] {
        guard let result = lastResult else {
            return defaultLearnCards
        }

        var cards: [LearnCard] = []

        if !result.personalTakeaway.isEmpty {
            cards.append(
                LearnCard(
                    title: "Today's nudge",
                    subtitle: result.personalTakeaway,
                    icon: "lightbulb.fill",
                    gradient: [Color(red: 0.85, green: 0.8, blue: 1.0), Color(red: 0.72, green: 0.65, blue: 1.0)]
                )
            )
        }

        if let focus = result.detectedIssues.first {
            cards.append(
                LearnCard(
                    title: "Focus on \(focus.key.capitalized)",
                    subtitle: focus.notes,
                    icon: "magnifyingglass.circle.fill",
                    gradient: [Color(red: 0.76, green: 0.84, blue: 1.0), Color(red: 0.63, green: 0.73, blue: 1.0)]
                )
            )
        }

        if let latestTags = historyStore.items.first?.contextTags,
           !latestTags.isEmpty {
            let tagTitles = latestTags.compactMap { tagId in
                StainTag.defaults.first(where: { $0.id == tagId })?.title
            }
            if !tagTitles.isEmpty {
                cards.append(
                    LearnCard(
                        title: "Watch the stains",
                        subtitle: tagTitles.joined(separator: ", "),
                        icon: "drop.fill",
                        gradient: [Color(red: 0.96, green: 0.86, blue: 0.74), Color(red: 0.93, green: 0.74, blue: 0.63)]
                    )
                )
            }
        }

        if cards.isEmpty {
            return defaultLearnCards
        }

        return cards
    }

    private var defaultLearnCards: [LearnCard] {
        [
            LearnCard(
                title: "How to brush for lasting whiteness",
                subtitle: "Two minutes, twice a day with micro-circular motions keeps enamel bright.",
                icon: "toothbrush.fill",
                gradient: [Color(red: 0.82, green: 0.91, blue: 1.0), Color(red: 0.68, green: 0.81, blue: 1.0)]
            ),
            LearnCard(
                title: "Foods that stain less",
                subtitle: "Crunchy greens and crisp apples whisk away surface stains naturally.",
                icon: "leaf.fill",
                gradient: [Color(red: 0.83, green: 0.93, blue: 0.84), Color(red: 0.69, green: 0.86, blue: 0.69)]
            )
        ]
    }

}

// MARK: - Supporting Models

private struct ShadeStage: Identifiable {
    let id = UUID()
    let milestoneTitle: String
    let descriptor: String
    let threshold: Double
    let gradient: [Color]
    let accentColor: Color

    static let defaults: [ShadeStage] = [
        ShadeStage(
            milestoneTitle: "Soft Yellow",
            descriptor: "Soft Yellow",
            threshold: 0,
            gradient: [Color(red: 0.99, green: 0.88, blue: 0.57), Color(red: 0.99, green: 0.8, blue: 0.41)],
            accentColor: Color(red: 0.98, green: 0.73, blue: 0.33)
        ),
        ShadeStage(
            milestoneTitle: "Ivory",
            descriptor: "Light Yellow",
            threshold: 3.5,
            gradient: [Color(red: 0.5, green: 0.73, blue: 1.0), Color(red: 0.59, green: 0.49, blue: 1.0)],
            accentColor: Color(red: 0.55, green: 0.57, blue: 1.0)
        ),
        ShadeStage(
            milestoneTitle: "Pearl",
            descriptor: "Pearl",
            threshold: 7.0,
            gradient: [Color(red: 0.78, green: 0.82, blue: 1.0), Color(red: 0.58, green: 0.68, blue: 1.0)],
            accentColor: Color(red: 0.55, green: 0.67, blue: 0.98)
        ),
        ShadeStage(
            milestoneTitle: "Your Dream Shade",
            descriptor: "Dream Shade",
            threshold: 9.0,
            gradient: [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.81, green: 0.87, blue: 1.0)],
            accentColor: Color(red: 0.72, green: 0.8, blue: 1.0)
        )
    ]
}

private struct Achievement: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let isUnlocked: Bool
}

private struct LearnCard: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
}

// MARK: - Home Hero

private struct HomeHeroCard: View {
    let greeting: String
    let emoji: String
    let userName: String
    let score: Double?
    let stage: ShadeStage
    let nextStage: ShadeStage?
    let deltaToNext: Double?
    let hasScan: Bool
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(greeting), \(userName)")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    if hasScan {
                        Text("Here's where your smile stands today.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Let's start your gleam journey.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(emoji)
                    .font(.system(size: 32))
            }

            HStack(alignment: .center, spacing: AppSpacing.l) {
                ScoreOrb(score: score, gradient: stage.gradient)

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    if let score {
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(stage.descriptor)
                            .font(.headline)
                            .foregroundStyle(stage.accentColor)
                        Text(progressMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ready to begin?")
                            .font(.title3.bold())
                        Text("Capture your first scan to unlock your personalized plan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            onScan()
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(FloatingPrimaryButtonStyle())
                        .padding(.top, AppSpacing.s)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 12)
        )
    }

    private var progressMessage: String {
        guard let delta = deltaToNext, let nextStage = nextStage else {
            return "You're glowing at your dream shade—keep shining!"
        }

        if delta < 0.2 {
            return "You're on the cusp of \(nextStage.descriptor.lowercased())!"
        }

        let formatted = String(format: "%.1f", delta)
        return "You're \(formatted) away from your next brightness level!"
    }
}

private struct ScoreOrb: View {
    let score: Double?
    let gradient: [Color]

    var body: some View {
        let glowColor = gradient.last ?? Color.blue

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 6)
                )

            if let score {
                VStack(spacing: AppSpacing.xs) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Score")
                        .font(.caption.bold())
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 120, height: 120)
        .shadow(color: glowColor.opacity(0.35), radius: 16, x: 0, y: 12)
    }
}

// MARK: - Journey Progress

private struct JourneyProgressSection: View {
    let score: Double?
    let stages: [ShadeStage]
    let nextStage: ShadeStage?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Your Journey to Gleam")
                    .font(.headline)
                Text(nextStageMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(progressGradient)
                        .frame(width: max(0, geometry.size.width * progress))
                        .animation(.easeInOut(duration: 0.8), value: progress)
                }
            }
            .frame(height: 12)

            HStack {
                ForEach(stages) { stage in
                    Text(stage.milestoneTitle)
                        .font(.caption2.weight(stage.milestoneTitle == currentStage.milestoneTitle ? .semibold : .regular))
                        .foregroundStyle(stage.milestoneTitle == currentStage.milestoneTitle ? stage.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
        )
    }

    private var progress: CGFloat {
        guard let score else { return 0 }
        return CGFloat(min(max(score / 10.0, 0), 1))
    }

    private var currentStage: ShadeStage {
        stages.last { stage in
            let value = score ?? 0
            return value >= stage.threshold
        } ?? stages.first!
    }

    private var nextStageMessage: String {
        guard let nextStage, let score else {
            return "Complete a scan to unlock your personal journey."
        }

        let remaining = nextStage.threshold - score
        if remaining <= 0 {
            return "You’re radiating at your dream shade."
        }

        let formatted = String(format: "%.1f", max(0, remaining))
        return "Only \(formatted) points until \(nextStage.milestoneTitle.lowercased())."
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: currentStage.gradient,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Daily Challenge

private struct DailyChallengeCard: View {
    let isCompletedToday: Bool
    let message: String
    let onScan: () -> Void
    let onCompare: () -> Void
    let latestResult: ScanResult?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(isCompletedToday ? "Challenge completed" : "Today's Challenge")
                .font(.headline)
            if !isCompletedToday {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: AppSpacing.s) {
                if !isCompletedToday {
                    Button {
                        onScan()
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(FloatingPrimaryButtonStyle())
                }

                Button {
                    onCompare()
                } label: {
                    Text("Compare Progress")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(FloatingSecondaryButtonStyle())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
        )
    }
}

// MARK: - Latest Insights

private struct LatestInsightsCard: View {
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
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Focus Areas")
                        .font(.subheadline.weight(.medium))
                    ForEach(result.detectedIssues.prefix(3), id: \.key) { issue in
                        HStack {
                            Circle()
                                .fill(severityColor(issue.severity))
                                .frame(width: 8, height: 8)
                            Text(issue.key.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            }

            Divider()
                .background(Color.primary.opacity(0.05))

            HStack {
                Label("\(confidenceValue)% confidence", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(result.shade, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
        )
    }

    private var confidenceValue: Int {
        Int((result.confidence * 100).rounded())
    }

    private var shadeDescription: String {
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

// MARK: - Achievements

private struct AchievementsSection: View {
    let achievements: [Achievement]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Smile Achievements")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.m) {
                    ForEach(achievements) { achievement in
                        AchievementBadge(achievement: achievement)
                    }
                }
            }
        }
    }
}

private struct AchievementBadge: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Text(achievement.emoji)
                .font(.title2)
                .padding(12)
                .background(
                    Circle()
                        .fill(Color.white.opacity(achievement.isUnlocked ? 0.9 : 0.4))
                )

            Text(achievement.title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(AppSpacing.s)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(achievement.isUnlocked ? 0.08 : 0.02), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .opacity(achievement.isUnlocked ? 1.0 : 0.45)
    }
}

// MARK: - Learn & Improve

private struct LearnAndImproveSection: View {
    let cards: [LearnCard]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Learn & Improve")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.m) {
                    ForEach(cards) { card in
                        LearnCardView(card: card)
                    }
                }
                .padding(.bottom, AppSpacing.xs)
            }
        }
    }
}

private struct LearnCardView: View {
    let card: LearnCard

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Image(systemName: card.icon)
                .font(.title2)
                .padding(10)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.2))
                )

            Text(card.title)
                .font(.headline)
                .lineLimit(2)

            Text(card.subtitle)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(3)
        }
        .padding(AppSpacing.m)
        .frame(width: 220, alignment: .leading)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: card.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Plan Components

private struct PlanPreviewCard: View {
    let plan: Recommendations
    let isPersonalized: Bool
    let status: PlanStatus?
    let onTap: () -> Void

    private var headline: String {
        isPersonalized ? "Your tailored plan" : "Personalized plan"
    }

    private var badgeText: String {
        isPersonalized ? "Tailored" : "Baseline"
    }

    private var highlights: [String] {
        let immediate = plan.immediate.first
        let daily = plan.daily.first
        let caution = plan.caution.first
        return [immediate, daily, caution].compactMap { $0 }
    }

    private var progressMessage: String {
        let refreshInterval = max(status?.refreshInterval ?? 10, 1)
        let planAvailable = status?.planAvailable ?? isPersonalized
        let remaining = max(status?.scansUntilNextPlan ?? refreshInterval, 0)

        if planAvailable {
            if remaining <= 0 {
                return "Your next scan refreshes this routine."
            }
            let noun = remaining == 1 ? "scan" : "scans"
            return "Next refresh in \(remaining) \(noun)."
        } else {
            if remaining <= 0 {
                return "One more scan unlocks your personalized plan."
            }
            let noun = remaining == 1 ? "scan" : "scans"
            return "\(remaining) more \(noun) to unlock your plan."
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack {
                    Text(headline)
                        .font(.headline)
                    Spacer()
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isPersonalized ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.15))
                        .foregroundStyle(isPersonalized ? Color.blue : Color.secondary)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(highlights, id: \.self) { item in
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(progressMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Tap to view the full routine")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.9))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .fill(AppColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlanSheetView: View {
    let plan: Recommendations
    let baselinePlan: Recommendations
    let status: PlanStatus?
    let isPersonalized: Bool

    private var planAvailable: Bool {
        status?.planAvailable ?? isPersonalized
    }

    private var refreshInterval: Int {
        max(status?.refreshInterval ?? 10, 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    PlanProgressBanner(status: status, isPersonalized: isPersonalized)
                        .accessibilityIdentifier("plan_progress_banner")

                    PlanTimelineView(
                        plan: plan,
                        sectionTitle: planAvailable ? "Your personalized routine" : "Baseline routine",
                        sectionDescription: planSectionDescription,
                        maxItemsPerCategory: 3
                    )

                    if planAvailable {
                        PlanTimelineView(
                            plan: baselinePlan,
                            sectionTitle: "Baseline essentials",
                            sectionDescription: "Keep these fundamentals in play between refreshes.",
                            maxItemsPerCategory: 3
                        )
                    }

                    Text("Plans refresh every \(refreshInterval) scans to stay aligned with your habits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Personalized plan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var planSectionDescription: String? {
        if planAvailable {
            return "Tailored from your recent scans and stain tags."
        }
        let remaining = max(status?.scansUntilNextPlan ?? refreshInterval, 0)
        if remaining <= 0 {
            return "Your next scan will unlock your tailored routine."
        }
        let noun = remaining == 1 ? "scan" : "scans"
        return "Complete \(remaining) more \(noun) to unlock your tailored routine."
    }
}

private struct PlanProgressBanner: View {
    let status: PlanStatus?
    let isPersonalized: Bool

    private var refreshInterval: Int {
        max(status?.refreshInterval ?? 10, 1)
    }

    private var planAvailable: Bool {
        status?.planAvailable ?? isPersonalized
    }

    private var remainingScans: Int {
        max(status?.scansUntilNextPlan ?? refreshInterval, 0)
    }

    private var icon: String {
        planAvailable ? "arrow.triangle.2.circlepath" : "sparkles"
    }

    private var tint: Color {
        planAvailable ? Color.accentColor : Color.secondary
    }

    private var headline: String {
        if planAvailable {
            if remainingScans <= 0 {
                return "Your next scan will refresh your personalized routine."
            } else if remainingScans == 1 {
                return "One more scan will refresh your personalized routine."
            } else {
                return "\(remainingScans) more scans until your refreshed routine."
            }
        } else {
            if remainingScans <= 0 {
                return "You're one scan away from unlocking your personalized routine."
            } else if remainingScans == 1 {
                return "One more scan unlocks your personalized routine."
            } else {
                return "\(remainingScans) more scans to unlock your personalized routine."
            }
        }
    }

    private var detail: String {
        planAvailable ?
            "We refresh your plan every \(refreshInterval) scans to keep pace with your progress." :
            "We build your first plan after \(refreshInterval) scans so it truly reflects your habits."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .top, spacing: AppSpacing.s) {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detail)
                .font(.footnote)
                .foregroundStyle(tint.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}


private struct PlanTimelineView: View {
    let plan: Recommendations
    let sectionTitle: String?
    let sectionDescription: String?
    let maxItemsPerCategory: Int

    init(
        plan: Recommendations,
        sectionTitle: String? = nil,
        sectionDescription: String? = nil,
        maxItemsPerCategory: Int = Int.max
    ) {
        self.plan = plan
        self.sectionTitle = sectionTitle
        self.sectionDescription = sectionDescription
        self.maxItemsPerCategory = max(1, maxItemsPerCategory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            if let sectionTitle {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(sectionTitle)
                        .font(.headline)
                    if let sectionDescription {
                        Text(sectionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(PlanCategory.allCases, id: \.self) { category in
                let items = items(for: category)
                if !items.isEmpty {
                    PlanTimelineRow(
                        title: category.title,
                        subtitle: category.subtitle,
                        icon: category.icon,
                        tint: category.tint,
                        items: items
                    )
                }
            }
        }
    }

    private func items(for category: PlanCategory) -> [String] {
        let list: [String]
        switch category {
        case .immediate:
            list = plan.immediate
        case .daily:
            list = plan.daily
        case .weekly:
            list = plan.weekly
        case .caution:
            list = plan.caution
        }
        return Array(list.prefix(maxItemsPerCategory))
    }
}

private enum PlanCategory: CaseIterable {
    case immediate, daily, weekly, caution

    var title: String {
        switch self {
        case .immediate: return "Immediate"
        case .daily: return "Daily rhythm"
        case .weekly: return "Weekly boost"
        case .caution: return "Caution"
        }
    }

    var subtitle: String {
        switch self {
        case .immediate: return "Start today"
        case .daily: return "Build the habit"
        case .weekly: return "Reset your smile"
        case .caution: return "Protect your progress"
        }
    }

    var icon: String {
        switch self {
        case .immediate: return "bolt.fill"
        case .daily: return "sun.max.fill"
        case .weekly: return "calendar.badge.plus"
        case .caution: return "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .immediate: return .blue
        case .daily: return .green
        case .weekly: return .purple
        case .caution: return .orange
        }
    }
}

private struct PlanTimelineRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.m) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}

