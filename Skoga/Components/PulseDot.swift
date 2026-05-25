import SwiftUI

/// 7pt status dot with a slowly expanding ring — `idle` skips the animation.
struct PulseDot: View {
    @Environment(\.palette) private var p
    let status: AgentStatus

    @State private var pulse = false

    private var color: Color {
        switch status {
        case .running: p.amber
        case .blocked: p.ember
        case .review:  p.dusk
        case .done:    p.forest
        case .idle:    p.inkFaint
        case .exited:  p.inkMute
        }
    }

    /// Statuses that don't represent active work — no pulse animation.
    private var isQuiet: Bool { status == .idle || status == .exited }

    var body: some View {
        ZStack {
            if !isQuiet {
                Circle()
                    .stroke(color, lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse ? 2.4 : 0.6)
                    .opacity(pulse ? 0 : 0.55)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 7, height: 7)
        .onAppear { if !isQuiet { pulse = true } }
    }
}
