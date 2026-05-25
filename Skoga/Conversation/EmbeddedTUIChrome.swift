import SwiftUI

/// Frames an embedded terminal view as if it were its own macOS app
/// window — traffic-light buttons, a monospaced title bar, and a footer
/// that reads "EMBEDDED TUI · LIVE". The chrome is purely visual; the
/// traffic lights don't do anything beyond signal "this is a separate
/// thing running inside Skoga". Companion to `RemoteTerminalView`.
struct EmbeddedTUIChrome<Content: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let subtitle: String
    let content: () -> Content

    init(title: String, subtitle: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusFooter
        }
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 12) {
                Text(title)
                    .font(SkogaFont.mono(11))
                    .foregroundStyle(p.ink2)
                Text(subtitle)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkFaint)
            }
            HStack {
                trafficLights
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 32)
        .background(p.paper3)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var trafficLights: some View {
        HStack(spacing: 8) {
            // Apple's macOS traffic-light colors. Decorative only — none
            // of these are wired to a window action because the embedded
            // terminal IS the pane, not a real movable window.
            Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
            Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18)).frame(width: 11, height: 11)
            Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 11, height: 11)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            SkogaGlyph(size: 14)
            Text("Skoga")
                .font(SkogaFont.smallMedium(11.5))
                .foregroundStyle(p.ink2)
            Spacer()
            Circle().fill(p.forest).frame(width: 6, height: 6)
            Text("EMBEDDED TUI · LIVE")
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.65)
                .foregroundStyle(p.inkFaint)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(p.paper3)
        .overlay(alignment: .top) { Hairline() }
    }
}
