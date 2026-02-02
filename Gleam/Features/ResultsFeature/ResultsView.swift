import SwiftUI
import UIKit

struct ResultsView: View {
    let result: ScanResult
    let historyItemId: String?
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var imageData: Data? = nil
    @State private var currentPage: Int = 0
    
    init(result: ScanResult, historyItemId: String? = nil) {
        self.result = result
        self.historyItemId = historyItemId
    }

    private var contextTagTitles: [String] {
        guard let tags = matchedHistoryItem?.contextTags else { return [] }
        return tags.compactMap { StainTag.title(for: $0) }
    }

    private var matchedHistoryItem: HistoryItem? {
        if let historyItemId,
           let item = historyStore.items.first(where: { $0.id == historyItemId }) {
            return item
        }
        return historyStore.items.first(where: { $0.result == result })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                SwipeableScoreArea(
                    score: normalizedScore(result.whitenessScore),
                    imageData: imageData,
                    currentPage: $currentPage
                )
                .frame(maxWidth: .infinity)

                if !contextTagTitles.isEmpty {
                    LifestyleTagSection(tags: contextTagTitles)
                }

                ResultHeadlineCard(
                    takeaway: result.personalTakeaway,
                    referralNeeded: result.referralNeeded
                )

                ShadeConfidenceCard(
                    shadeCode: result.shade,
                    shadeDescription: shadeDescription,
                    confidence: result.confidence
                )

                if !result.detectedIssues.isEmpty {
                    DetectedIssuesSection(issues: result.detectedIssues)
                }

                ShareLink(item: shareText(for: result)) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Text(result.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, AppSpacing.l)
            }
            .padding()
        }
        .navigationTitle("Results")
        .background(AppBackground())
        .task {
            // Load image if historyItemId is available
            if let historyItemId = historyItemId {
                imageData = await historyStore.loadImage(for: historyItemId)
            }
        }
        .onChange(of: imageData) { _, _ in
            // Reset to score ring when image loads
            currentPage = 0
        }
    }
    
    private func normalizedScore(_ rawScore: Int) -> Double {
        // Convert 0-100 to 0-10 scale
        return Double(rawScore) / 10.0
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
}

// MARK: - Swipeable Score Area
private struct SwipeableScoreArea: View {
    let score: Double
    let imageData: Data?
    @Binding var currentPage: Int
    @State private var containerHeight: CGFloat = 280
    @State private var dragOffset: CGFloat = 0
    
    private var hasImage: Bool {
        imageData != nil && UIImage(data: imageData!) != nil
    }
    
    private var photoAspectRatio: CGFloat? {
        guard let imageData = imageData,
              let uiImage = UIImage(data: imageData) else {
            return nil
        }
        let size = uiImage.size
        return size.height / size.width
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let photoWidth = screenWidth * 0.75 // 75% of screen width
            let maxPhotoHeight = min(geometry.size.height * 2, 450)
            let calculatedPhotoHeight = photoAspectRatio.map { 
                min($0 * photoWidth, maxPhotoHeight)
            } ?? 280
            
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    // Page 0: Score Ring - first view (default)
                    ScoreRing(score: score)
                        .frame(width: screenWidth, height: 280)
                    
                    // Page 1: Photo (only if available) - revealed when swiped left
                    if hasImage, let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: photoWidth, height: containerHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(width: screenWidth) // Center in full width
                    }
                }
                .offset(x: hasImage ? -CGFloat(currentPage) * screenWidth + dragOffset : 0)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25), value: currentPage)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if hasImage {
                                // Allow dragging between pages
                                let translation = value.translation.width
                                if (currentPage == 0 && translation < 0) || (currentPage == 1 && translation > 0) {
                                    dragOffset = translation * 0.5 // Add resistance
                                }
                            }
                        }
                        .onEnded { value in
                            if hasImage {
                                let translation = value.translation.width
                                let velocity = value.predictedEndTranslation.width - translation
                                
                                // Determine if we should change page
                                let threshold: CGFloat = screenWidth * 0.3
                                let shouldChangePage = abs(translation) > threshold || abs(velocity) > 200
                                
                                if translation < 0 && currentPage == 0 && shouldChangePage {
                                    // Swipe left to reveal photo
                                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25)) {
                                        currentPage = 1
                                        containerHeight = calculatedPhotoHeight
                                    }
                                } else if translation > 0 && currentPage == 1 && shouldChangePage {
                                    // Swipe right to go back to score
                                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25)) {
                                        currentPage = 0
                                        containerHeight = 280
                                    }
                                }
                                
                                // Reset drag offset
                                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                
                // Page indicator dots (only show when image is available)
                if hasImage {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(currentPage == 0 ? Color.primary : Color.primary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                        
                        Circle()
                            .fill(currentPage == 1 ? Color.primary : Color.primary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                    .padding(.top, 4)
                }
            }
            .onChange(of: currentPage) { _, newPage in
                // Update container height when page changes
                if hasImage {
                    let photoWidth = screenWidth * 0.75
                    let maxPhotoHeight = min(geometry.size.height * 2, 450)
                    let photoHeight = photoAspectRatio.map { 
                        min($0 * photoWidth, maxPhotoHeight)
                    } ?? 280
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.25)) {
                        containerHeight = newPage == 1 ? photoHeight : 280
                    }
                }
            }
        }
        .frame(height: containerHeight + (hasImage ? 32 : 0)) // Extra space for dots
        .clipped()
    }
}

// MARK: - Score Ring
private struct ScoreRing: View {
    let score: Double // 0-10 scale
    @State private var animatedScore: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            let availableSize = min(geometry.size.width, geometry.size.height)
            let circleSize = min(availableSize * 0.8, 220) // Use 80% of available space, max 220
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 20)
                    .frame(width: circleSize, height: circleSize)
                Circle()
                    .trim(from: 0, to: min(1.0, animatedScore / 10.0))
                    .stroke(scoreGradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.7), value: animatedScore)
                    .frame(width: circleSize, height: circleSize)
                
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", animatedScore))
                        .font(.system(size: min(64, circleSize * 0.32), weight: .bold, design: .rounded))
                        .foregroundStyle(scoreGradient)
                        .contentTransition(.numericText(value: animatedScore))
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: animatedScore)
                    
                    Text("/ 10")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    
                    Text(scoreLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(scoreLabelColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(scoreLabelColor.opacity(0.15))
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, AppSpacing.l) // Add vertical padding to ensure full visibility
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2)) {
                animatedScore = score
            }
        }
    }
    
    private var scoreGradient: LinearGradient {
        let colors: [Color]
        if animatedScore >= 8.0 {
            colors = [.green, .mint]
        } else if animatedScore >= 6.0 {
            colors = [.blue, .cyan]
        } else if animatedScore >= 4.0 {
            colors = [.orange, .yellow]
        } else {
            colors = [.red, .orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private var scoreLabel: String {
        if animatedScore >= 9.0 { return "✨ Brilliant" }
        if animatedScore >= 8.0 { return "🌟 Excellent" }
        if animatedScore >= 7.0 { return "🎯 Great" }
        if animatedScore >= 6.0 { return "👍 Good" }
        if animatedScore >= 5.0 { return "📈 Improving" }
        if animatedScore >= 3.0 { return "💪 Keep Going" }
        return "🚀 Start Here"
    }
    
    private var scoreLabelColor: Color {
        if animatedScore >= 8.0 { return .green }
        if animatedScore >= 6.0 { return .blue }
        if animatedScore >= 4.0 { return .orange }
        return .red
    }
}

// MARK: - Lifestyle Tags
private struct LifestyleTagSection: View {
    let tags: [String]

    var body: some View {
        InsightCard(title: "Lifestyle tags", icon: "leaf.fill") {
            LifestyleTagGrid(tags: tags)
        }
    }
}

private struct LifestyleTagGrid: View {
    let tags: [String]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: AppSpacing.s)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
            ForEach(tags, id: \.self) { tag in
                LifestyleTagChip(label: tag)
            }
        }
    }
}

private struct LifestyleTagChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xs)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}

private func shareText(for result: ScanResult) -> String {
    var lines: [String] = []
    lines.append("Gleam Whitening Summary")
    lines.append("Score: \(result.whitenessScore)")
    lines.append("Takeaway: \(result.personalTakeaway)")
    lines.append("Shade: \(result.shade)")
    return lines.joined(separator: "\n")
}

// MARK: - Result Detail Components
private struct ResultHeadlineCard: View {
    let takeaway: String
    let referralNeeded: Bool

    var body: some View {
        InsightCard(title: "Personal Takeaway", icon: "sparkles") {
            Text(takeaway)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if referralNeeded {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cross.case.fill")
                        .foregroundStyle(.red)
                    Text("Consider scheduling a professional consultation to review these findings in more detail.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }
    }
}

private struct ShadeConfidenceCard: View {
    let shadeCode: String
    let shadeDescription: String
    let confidence: Double

    private var confidenceValue: Double {
        min(max(confidence, 0.0), 1.0)
    }

    private var confidenceLabel: String {
        let percentage = Int(confidenceValue * 100)
        switch percentage {
        case 0...40: return "Low confidence"
        case 41...70: return "Moderate confidence"
        default: return "High confidence"
        }
    }

    var body: some View {
        InsightCard(title: "Shade & Confidence", icon: "paintpalette.fill") {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack(alignment: .center, spacing: AppSpacing.m) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(shadeDescription)
                            .font(.title3.bold())
                        Text("Shade \(shadeCode)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ShadeSwatchView(shadeCode: shadeCode)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text("Model confidence")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(confidenceValue * 100))%")
                            .font(.subheadline.weight(.bold))
                    }

                    ProgressView(value: confidenceValue)
                        .tint(.blue)

                    Text(confidenceLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DetectedIssuesSection: View {
    let issues: [DetectedIssue]

    var body: some View {
        InsightCard(title: "Focus Areas", icon: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                ForEach(issues, id: \.key) { issue in
                    IssueCard(issue: issue)
                }
            }
        }
    }
}

private struct IssueCard: View {
    let issue: DetectedIssue

    private var severityColor: Color {
        switch issue.severity.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(issue.key.capitalized)
                    .font(.headline)
                Spacer()
                Text(issue.severity.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(severityColor.opacity(0.1))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())
            }

            Text(issue.notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct InsightCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }
}

private struct ShadeSwatchView: View {
    let shadeCode: String

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(shadeGradient(for: shadeCode))
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
            Text(shadeLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var shadeLabel: String {
        shadeCode.uppercased()
    }

    private func shadeGradient(for shade: String) -> LinearGradient {
        let start: Color
        let end: Color
        switch shade.uppercased() {
        case "A1": (start, end) = (.yellow.opacity(0.25), .white)
        case "A2": (start, end) = (.yellow.opacity(0.35), .white)
        case "A3": (start, end) = (.yellow.opacity(0.5), .white)
        case "B1": (start, end) = (.mint.opacity(0.25), .white)
        case "B2": (start, end) = (.mint.opacity(0.4), .white)
        case "B3": (start, end) = (.mint.opacity(0.55), .white)
        case "C1": (start, end) = (.orange.opacity(0.35), .white)
        case "C2": (start, end) = (.orange.opacity(0.5), .white)
        case "C3": (start, end) = (.orange.opacity(0.6), .white)
        case "D2": (start, end) = (.brown.opacity(0.4), .white)
        case "D3": (start, end) = (.brown.opacity(0.55), .white)
        case "D4": (start, end) = (.brown.opacity(0.7), .white)
        default: (start, end) = (.blue.opacity(0.2), .white)
        }
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}


