import SwiftUI

struct StatusPill: View {
    @Environment(\.palette) private var p
    let status: AgentStatus

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

    var body: some View {
        HStack(spacing: 5) {
            PulseDot(status: status)
            Text(status.label.uppercased())
                .font(SkogaFont.monoTiny(10))
                .tracking(0.6)
        }
        .foregroundStyle(color)
    }
}
