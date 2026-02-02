import Foundation
import SwiftUI
import Combine
import UIKit

enum FlowQuadrant: String, CaseIterable {
    case upperRight = "Upper Right"
    case upperLeft = "Upper Left"
    case lowerLeft = "Lower Left"
    case lowerRight = "Lower Right"
    
    var instruction: String {
        switch self {
        case .upperRight: return "Start with the upper right"
        case .upperLeft: return "Switch to upper left"
        case .lowerLeft: return "Move to lower left"
        case .lowerRight: return "Finish with lower right"
        }
    }
}

enum FlowStatus {
    case idle
    case running
    case paused
    case completed
}

@MainActor
final class FlowEngine: ObservableObject {
    @Published private(set) var timeRemaining: Double = 120
    @Published private(set) var totalDuration: Double = 120
    @Published private(set) var currentQuadrant: FlowQuadrant = .upperRight
    @Published private(set) var status: FlowStatus = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentBriefing: DailyBriefing?
    
    private var timer: Timer?
    private var startDate: Date?
    private var pausedTimeRemaining: Double?
    
    // Haptics
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private let quadrantDuration: Double = 30
    
    init() {
        prepareHaptics()
    }
    
    func start() {
        guard status == .idle || status == .paused else { return }
        
        if status == .idle {
            timeRemaining = totalDuration
            currentQuadrant = .upperRight
            progress = 0
            currentBriefing = BriefingProvider.shared.dailyBriefing()
        }
        
        status = .running
        prepareHaptics()
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    func pause() {
        guard status == .running else { return }
        status = .paused
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        timer?.invalidate()
        timer = nil
        status = .idle
        timeRemaining = totalDuration
        currentQuadrant = .upperRight
        progress = 0
    }
    
    private func tick() {
        guard timeRemaining > 0 else {
            complete()
            return
        }
        
        timeRemaining -= 0.1
        progress = 1.0 - (timeRemaining / totalDuration)
        
        updateQuadrant()
    }
    
    private func updateQuadrant() {
        let elapsedTime = totalDuration - timeRemaining
        let quadrantIndex = Int(elapsedTime / quadrantDuration)
        
        let newQuadrant: FlowQuadrant
        if quadrantIndex < FlowQuadrant.allCases.count {
            newQuadrant = FlowQuadrant.allCases[quadrantIndex]
        } else {
            newQuadrant = .lowerRight // Fallback
        }
        
        if newQuadrant != currentQuadrant {
            currentQuadrant = newQuadrant
            triggerQuadrantHaptic()
        }
    }
    
    private func complete() {
        status = .completed
        timer?.invalidate()
        timer = nil
        triggerCompletionHaptic()
    }
    
    private func prepareHaptics() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    private func triggerQuadrantHaptic() {
        impactGenerator.impactOccurred(intensity: 1.0)
    }
    
    private func triggerCompletionHaptic() {
        notificationGenerator.notificationOccurred(.success)
    }
}
