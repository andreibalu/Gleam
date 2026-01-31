import SwiftUI

struct FlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = FlowEngine()
    @State private var animateGradient = false
    
    // Callback to notify parent of completion
    var onComplete: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Immersive Background
            BreathingBackground()
                .ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Button {
                        engine.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Main Content
                if engine.status == .completed {
                    CompletionView {
                        onComplete?()
                        dismiss()
                    }
                } else {
                    ActiveSessionView(engine: engine)
                }
                
                Spacer()
                
                // Footer / Controls
                if engine.status != .completed {
                    HStack(spacing: 30) {
                        if engine.status == .paused {
                            Button {
                                engine.start()
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Button {
                                engine.pause()
                            } label: {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            engine.start()
        }
    }
}

private struct ActiveSessionView: View {
    @ObservedObject var engine: FlowEngine
    
    var body: some View {
        VStack(spacing: 40) {
            // Quadrant Indicator
            Text(engine.currentQuadrant.instruction)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .transition(.opacity.combined(with: .scale))
                .id(engine.currentQuadrant) // Forces transition on change
            
            // Timer Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: engine.progress)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: engine.progress)
                
                Text(timeString(from: engine.timeRemaining))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 220, height: 220)
            
            // Daily Briefing
            if let briefing = engine.currentBriefing {
                VStack(spacing: 12) {
                    Text(briefing.content)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let author = briefing.author {
                        Text("— \(author)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .transition(.opacity)
                .animation(.easeIn(duration: 1.0), value: briefing.id)
            }
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct CompletionView: View {
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeating)
            
            Text("Gleam Complete")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            
            Text("Your smile is glowing.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
            
            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 20)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(duration: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

private struct BreathingBackground: View {
    @State private var start = UnitPoint(x: 0, y: -2)
    @State private var end = UnitPoint(x: 4, y: 0)
    
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.2, green: 0.3, blue: 0.8),
                Color(red: 0.4, green: 0.6, blue: 0.9),
                Color(red: 0.2, green: 0.8, blue: 0.7)
            ],
            startPoint: start,
            endPoint: end
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                start = UnitPoint(x: 1, y: 0)
                end = UnitPoint(x: 0, y: 2)
            }
        }
    }
}
