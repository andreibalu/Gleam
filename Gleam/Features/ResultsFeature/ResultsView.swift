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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                // Swipeable Score Ring / Photo Area with dynamic height
                SwipeableScoreArea(
                    score: normalizedScore(result.whitenessScore),
                    imageData: imageData,
                    currentPage: $currentPage
                )
                .frame(maxWidth: .infinity)

                GroupBox("Shade Classification") {
                    HStack {
                        Label(shadeDescription, systemImage: "eyedropper")
                            .font(.subheadline)
                        Spacer()
                        Text(result.shade)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                GroupBox("Detected Issues") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        ForEach(result.detectedIssues, id: \.key) { issue in
                            HStack {
                                Text(issue.key.capitalized)
                                Spacer()
                                Text(issue.severity)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Plan") {
                    PlanSection(title: "Immediate", items: result.recommendations.immediate)
                    PlanSection(title: "Daily", items: result.recommendations.daily)
                    PlanSection(title: "Weekly", items: result.recommendations.weekly)
                    PlanSection(title: "Caution", items: result.recommendations.caution)
                }

                ShareLink(item: shareText(for: result)) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Text(result.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Results")
        .background(AppColors.background.ignoresSafeArea())
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

private struct PlanSection: View {
    let title: String
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(title).font(.headline)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(item)
                    }
                }
            }
            .padding(.vertical, AppSpacing.s)
        }
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

private func shareText(for result: ScanResult) -> String {
    var lines: [String] = []
    lines.append("Gleam Whitening Summary")
    lines.append("Score: \(result.whitenessScore)")
    lines.append("Shade: \(result.shade)")
    if !result.recommendations.immediate.isEmpty { lines.append("Immediate: \(result.recommendations.immediate.joined(separator: ", "))") }
    if !result.recommendations.daily.isEmpty { lines.append("Daily: \(result.recommendations.daily.joined(separator: ", "))") }
    if !result.recommendations.weekly.isEmpty { lines.append("Weekly: \(result.recommendations.weekly.joined(separator: ", "))") }
    if !result.recommendations.caution.isEmpty { lines.append("Caution: \(result.recommendations.caution.joined(separator: ", "))") }
    return lines.joined(separator: "\n")
}


