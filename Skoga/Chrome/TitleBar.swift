import SwiftUI

/// Custom 44pt titlebar. Traffic lights are the real OS ones (positioned by
/// `WindowAccessor`); we render the center context label and right-side
/// buttons over the parchment.
struct TitleBar: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            // Background + drag region
            p.paper2
            WindowDragRegion()

            // Hairline at bottom
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Hairline()
            }

            // Centered context label — "skoga · Roster · 12 agents"
            HStack(spacing: 6) {
                Text("skoga")
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.ink2)
                    .fontWeight(.medium)
                Text("·")
                    .foregroundStyle(p.inkMute)
                Text(state.contextLabel.uppercased())
                    .font(SkogaFont.mono(11))
                    .tracking(0.65)
                    .foregroundStyle(p.inkMute)
            }

            // Trailing controls
            HStack(spacing: 6) {
                Spacer()
                GhostButton(label: "Command", icon: .search, trailingKbd: "⌘K") {
                    state.commandPaletteOpen = true
                }
                GhostIconButton(icon: .watch) {}
                GhostIconButton(icon: .settings, active: state.view == .settings) {
                    state.view = .settings
                    state.openAgentId = nil
                }
            }
            .padding(.trailing, 14)
        }
        .frame(height: Tokens.titlebarHeight)
        // Pad the leading edge past the traffic lights (NSWindowButton cluster ≈ 72pt).
        .padding(.leading, 0)
    }
}

// MARK: – Buttons

struct GhostButton: View {
    @Environment(\.palette) private var p
    let label: String
    let icon: SkogaIcon?
    let trailingKbd: String?
    let action: () -> Void

    @State private var hovering = false

    init(label: String, icon: SkogaIcon? = nil, trailingKbd: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.trailingKbd = trailingKbd
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(skoga: icon).skogaIconSize(12) }
                Text(label)
                    .font(SkogaFont.smallMedium(11.5))
                if let kbd = trailingKbd {
                    Text(kbd)
                        .font(SkogaFont.monoTiny(10))
                        .foregroundStyle(p.inkMute)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                .fill(p.paper2)
                                .hairlineBorder(p.rule, radius: Tokens.Radius.tiny)
                        )
                }
            }
            .foregroundStyle(hovering ? p.ink : p.ink2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering ? p.paper3 : p.paper)
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct GhostIconButton: View {
    @Environment(\.palette) private var p
    let icon: SkogaIcon
    var active: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(skoga: icon).skogaIconSize(12)
                .foregroundStyle(active ? p.forest : (hovering ? p.ink : p.ink2))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(active ? p.paper4 : (hovering ? p.paper3 : p.paper))
                        .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
