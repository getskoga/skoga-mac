import SwiftUI

struct StatusPill: View {
    @Environment(\.palette) private var p
    let status: AgentStatus

    private var color: Color {
        switch status {
        case .running:  p.amber
        case .blocked:  p.ember
        case .prOpen:   p.dusk
        case .prMerged: p.forest
        case .prClosed: p.inkMute
        case .done:     p.forest
        case .idle:     p.inkFaint
        case .stopping: p.ember
        case .exited:   p.inkMute
        case .killed:   p.inkMute
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
