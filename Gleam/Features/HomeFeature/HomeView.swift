import SwiftUI

private enum PlanDisplayMode: String {
    case personalized
    case baseline
}

struct HomeView: View {
    @Environment(\.scanRepository) private var scanRepository
    @EnvironmentObject private var scanSession: ScanSession
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var achievementManager: AchievementManager
    @AppStorage("userFirstName") private var userFirstName: String = "Andrei"
    @AppStorage("planDisplayMode") private var planDisplayModeRawValue: String = PlanDisplayMode.personalized.rawValue
    @State private var lastResult: ScanResult?
    @State private var showCamera = false
    @State private var showPlanSheet = false
    @State private var personalizedPlan: PlanOutcome?
    @State private var hasSyncedCloudState = false
    @State private var showAchievementsModal = false

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
        guard isPersonalizedPlanActive, let tailoredPlan = personalizedPlan?.plan else {
            return defaultPlan
        }
        return tailoredPlan
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

    private var selectedPlanDisplayMode: PlanDisplayMode {
        PlanDisplayMode(rawValue: planDisplayModeRawValue) ?? .personalized
    }

    private var isPersonalizedPlanActive: Bool {
        hasPersonalizedPlan && selectedPlanDisplayMode == .personalized
    }

    private var planDisplayModeBinding: Binding<PlanDisplayMode> {
        Binding(
            get: { selectedPlanDisplayMode },
            set: { newValue in
                if newValue == .personalized && !hasPersonalizedPlan {
                    planDisplayModeRawValue = PlanDisplayMode.baseline.rawValue
                } else {
                    planDisplayModeRawValue = newValue.rawValue
                }
            }
        )
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
                    isPersonalized: isPersonalizedPlanActive,
                    status: planStatus,
                    onTap: { showPlanSheet = true },
                    hasAvailablePersonalizedPlan: hasPersonalizedPlan
                )

                if let result = lastResult {
                    LatestInsightsCard(result: result)
                }

                AchievementsTrayView {
                    showAchievementsModal = true
                }

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
                personalizedPlan: personalizedPlan?.plan,
                baselinePlan: defaultPlan,
                status: planStatus,
                canUsePersonalizedPlan: hasPersonalizedPlan,
                displayMode: planDisplayModeBinding
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAchievementsModal) {
            AchievementsCollectionModal()
                .environmentObject(achievementManager)
        }
        .overlay(alignment: .center) {
            if let celebration = achievementManager.activeCelebration {
                BadgeUnlockCelebrationView(celebration: celebration) {
                    achievementManager.dismissCelebration(celebration)
                }
                .transition(.scale.combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: achievementManager.activeCelebration?.id)
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

private struct AchievementsTrayView: View {
    @EnvironmentObject private var achievementManager: AchievementManager
    let onTap: () -> Void

    private var unlocked: [AchievementSnapshot] {
        achievementManager.unlockedSnapshots
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smile Achievements")
                        .font(.headline)
                    Text(unlocked.isEmpty ? "Unlock your first badge to reveal it here." : "Tap to see your full trophy case.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Text("View all")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.m) {
                    if unlocked.isEmpty {
                        LockedBadgePlaceholder()
                    } else {
                        ForEach(unlocked) { snapshot in
                            UnlockedAchievementBadge(snapshot: snapshot)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
        )
        .onTapGesture {
            onTap()
        }
        .accessibilityAddTraits(.isButton)
    }
}

private struct LockedBadgePlaceholder: View {
    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("No badges yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.s)
        .frame(width: 110)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

private struct UnlockedAchievementBadge: View {
    let snapshot: AchievementSnapshot

    private var gradient: LinearGradient {
        let colors = snapshot.definition.id.badgeGradient
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: 74, height: 74)
                    .shadow(color: gradient.colors.last?.opacity(0.35) ?? .blue.opacity(0.3), radius: 10, x: 0, y: 8)
                Image(systemName: snapshot.definition.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(snapshot.definition.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(snapshot.tier.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(AppSpacing.s)
        .frame(width: 120)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct AchievementsCollectionModal: View {
    @EnvironmentObject private var achievementManager: AchievementManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.m),
        GridItem(.flexible(), spacing: AppSpacing.m)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppSpacing.l) {
                    ForEach(achievementManager.snapshots) { snapshot in
                        AchievementGridCard(snapshot: snapshot)
                    }
                }
                .padding()
            }
            .navigationTitle("Achievements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct AchievementGridCard: View {
    let snapshot: AchievementSnapshot

    private var tint: Color {
        snapshot.definition.id.badgeGradient.first ?? .accentColor
    }

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.12), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: snapshot.progressFraction)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.85), value: snapshot.progressFraction)

                Image(systemName: snapshot.definition.icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(snapshot.isUnlocked ? .white : Color.primary.opacity(0.35))
                    .padding(26)
                    .background(
                        Circle()
                            .fill(snapshot.isUnlocked ? tint : Color.primary.opacity(0.05))
                    )
                    .scaleEffect(snapshot.isUnlocked ? 1.05 : 0.95)
            }
            .frame(width: 140, height: 140)

            VStack(spacing: 4) {
                Text(snapshot.definition.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(snapshot.isUnlocked ? snapshot.tier.label : snapshot.progressLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let nextTier = snapshot.nextTierLabel {
                Text(snapshot.isUnlocked ? "Next: \(nextTier)" : "Goal: \(nextTier)")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.9))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 12)
        )
    }
}

private struct BadgeUnlockCelebrationView: View {
    let celebration: AchievementCelebration
    let onDismiss: () -> Void

    @State private var animatePulse = false
    @State private var emitConfetti = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: AppSpacing.m) {
                Text("Badge unlocked")
                    .font(.title2.weight(.bold))
                Text(celebration.title)
                    .font(.headline)
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: celebration.achievementId.badgeGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 14)
                        .scaleEffect(animatePulse ? 1 : 0.7)
                        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: animatePulse)
                    Image(systemName: celebration.icon)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(animatePulse ? 1.05 : 0.8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: animatePulse)
                }

                Text(celebration.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    dismiss()
                } label: {
                    Text("Keep gleaming")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FloatingPrimaryButtonStyle())
            }
            .padding(AppSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, AppSpacing.l)

            ConfettiLayerView(isEmitting: $emitConfetti)
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !animatePulse else { return }
            animatePulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                emitConfetti = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        emitConfetti = false
        onDismiss()
    }
}

private struct ConfettiLayerView: View {
    @Binding var isEmitting: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<20, id: \.self) { index in
                    ConfettiPiece(
                        seed: index,
                        canvasSize: geometry.size,
                        isEmitting: $isEmitting
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ConfettiPiece: View {
    let seed: Int
    let canvasSize: CGSize
    @Binding var isEmitting: Bool

    private var colors: [Color] {
        [
            Color(red: 0.99, green: 0.73, blue: 0.38),
            Color(red: 0.74, green: 0.67, blue: 1.0),
            Color(red: 0.58, green: 0.87, blue: 0.96),
            Color(red: 0.95, green: 0.56, blue: 0.74),
            Color(red: 0.64, green: 0.85, blue: 0.52)
        ]
    }

    private var offset: CGSize {
        let width = canvasSize.width * 0.8
        let height = canvasSize.height * 0.6
        let normalized = CGFloat((seed * 73) % 100) / 100.0
        let x = (normalized - 0.5) * width
        let y = height + CGFloat(seed % 4) * 20
        return CGSize(width: x, height: y)
    }

    private var rotation: Double {
        Double((seed * 137) % 360)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(colors[seed % colors.count])
            .frame(width: 6, height: 12)
            .rotationEffect(.degrees(isEmitting ? rotation : 0))
            .offset(x: isEmitting ? offset.width : 0, y: isEmitting ? offset.height : 0)
            .opacity(isEmitting ? 0 : 1)
            .animation(.easeOut(duration: 1.3).delay(Double(seed) * 0.02), value: isEmitting)
    }
}

private extension AchievementID {
    var badgeGradient: [Color] {
        switch self {
        case .streakLegend:
            return [Color(red: 0.99, green: 0.69, blue: 0.42), Color(red: 0.97, green: 0.38, blue: 0.41)]
        case .glowScore:
            return [Color(red: 0.64, green: 0.56, blue: 0.99), Color(red: 0.33, green: 0.41, blue: 0.94)]
        case .scanCollector:
            return [Color(red: 0.43, green: 0.84, blue: 0.99), Color(red: 0.15, green: 0.63, blue: 0.90)]
        case .stainStrategist:
            return [Color(red: 0.44, green: 0.89, blue: 0.76), Color(red: 0.19, green: 0.65, blue: 0.55)]
        }
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
    let hasAvailablePersonalizedPlan: Bool

    private var headline: String {
        isPersonalized ? "Your tailored plan" : "Baseline routine"
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
        let remaining = max(status?.scansUntilNextPlan ?? refreshInterval, 0)
        let planAvailable = status?.planAvailable ?? hasAvailablePersonalizedPlan

        if isPersonalized {
            if planAvailable {
                if remaining <= 0 {
                    return "Your next scan refreshes this routine."
                }
                let noun = remaining == 1 ? "scan" : "scans"
                return "Next refresh in \(remaining) \(noun)."
            } else {
                if remaining <= 0 {
                    return "Your next scan unlocks your personalized plan."
                }
                let noun = remaining == 1 ? "scan" : "scans"
                return "\(remaining) more \(noun) to unlock your plan."
            }
        } else {
            if planAvailable {
                return "Baseline routine active. Toggle on your tailored plan anytime."
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
    let personalizedPlan: Recommendations?
    let baselinePlan: Recommendations
    let status: PlanStatus?
    let canUsePersonalizedPlan: Bool
    @Binding var displayMode: PlanDisplayMode

    private var refreshInterval: Int {
        max(status?.refreshInterval ?? 10, 1)
    }

    private var planAvailable: Bool {
        status?.planAvailable ?? canUsePersonalizedPlan
    }

    private var isPersonalizedActive: Bool {
        canUsePersonalizedPlan && displayMode == .personalized && personalizedPlan != nil
    }

    private var activePlan: Recommendations {
        if isPersonalizedActive, let personalizedPlan {
            return personalizedPlan
        }
        return baselinePlan
    }

    private var activeSectionTitle: String {
        isPersonalizedActive ? "Your personalized routine" : "Baseline routine"
    }

    private var activeSectionDescription: String? {
        sectionDescription(for: isPersonalizedActive ? .personalized : .baseline)
    }

    private var personalizedToggleBinding: Binding<Bool> {
        Binding(
            get: { isPersonalizedActive },
            set: { newValue in
                displayMode = (newValue && planAvailable) ? .personalized : .baseline
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Toggle(isOn: personalizedToggleBinding) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Use tailored plan")
                                    .font(.headline)
                                Text(toggleSubtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .disabled(!planAvailable)
                        .accessibilityIdentifier("plan_mode_toggle")

                        if !planAvailable {
                            Text("Keep scanning—your tailored routine unlocks automatically soon.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PlanProgressBanner(
                        status: status,
                        isPersonalized: isPersonalizedActive,
                        hasAvailablePersonalizedPlan: planAvailable
                    )
                    .accessibilityIdentifier("plan_progress_banner")

                    PlanTimelineView(
                        plan: activePlan,
                        sectionTitle: activeSectionTitle,
                        sectionDescription: activeSectionDescription,
                        maxItemsPerCategory: 3
                    )

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

    private func sectionDescription(for mode: PlanDisplayMode) -> String? {
        switch mode {
        case .personalized:
            if planAvailable {
                return "Tailored from your recent scans and stain tags."
            }
            let remaining = max(status?.scansUntilNextPlan ?? refreshInterval, 0)
            if remaining <= 0 {
                return "Your next scan will unlock your tailored routine."
            }
            let noun = remaining == 1 ? "scan" : "scans"
            return "Complete \(remaining) more \(noun) to unlock your tailored routine."
        case .baseline:
            if planAvailable {
                return "Steady essentials to follow whenever you pause the tailored routine."
            } else {
                return "Follow these essentials while we finish preparing your tailored routine."
            }
        }
    }

    private var toggleSubtitle: String {
        if planAvailable {
            return "Switch off to follow the baseline essentials instead."
        } else {
            return "Baseline essentials stay active until your tailored plan is ready."
        }
    }
}

private struct PlanProgressBanner: View {
    let status: PlanStatus?
    let isPersonalized: Bool
    let hasAvailablePersonalizedPlan: Bool

    private var refreshInterval: Int {
        max(status?.refreshInterval ?? 10, 1)
    }

    private var planAvailable: Bool {
        status?.planAvailable ?? hasAvailablePersonalizedPlan
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

