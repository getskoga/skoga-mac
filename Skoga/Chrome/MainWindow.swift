import SwiftUI

struct MainWindow: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            // Background covers the whole window (under the hidden titlebar too).
            p.paper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TitleBar()
                DaemonStatusBanner(status: state.daemonStatus)
                HStack(spacing: 0) {
                    Sidebar()
                    mainArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let toast = state.toast {
                VStack {
                    Spacer()
                    ToastView(text: toast).padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let id = state.prAgentId, let agent = state.agents.first(where: { $0.id == id }) {
                PRModal(agent: agent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let id = state.stopAgentId, let agent = state.agents.first(where: { $0.id == id }) {
                StopConfirmModal(agent: agent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if state.commandPaletteOpen {
                CommandPalette()
                    .transition(.opacity)
            }
        }
        .onExitCommand { state.commandPaletteOpen = false }
        .background(WindowAccessor())
        .animation(.easeOut(duration: 0.2), value: state.toast)
        .animation(.easeOut(duration: 0.15), value: state.view)
    }

    @ViewBuilder private var mainArea: some View {
        VStack(spacing: 0) {
            switch state.view {
            case .roster:
                CockpitStrip()
                RosterView()
            case .conversation:
                if let agent = state.openAgent {
                    ConversationView(agent: agent)
                } else {
                    placeholderView
                }
            case .dispatch:
                DispatchView()
            case .review:
                ReviewView()
            case .telemetry:
                TelemetryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var placeholderView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(state.view.rawValue.capitalized)
                .font(SkogaFont.serifTitle(28))
                .foregroundStyle(p.ink)
            Text("This view lands in the next slice.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: – Toast

struct ToastView: View {
    @Environment(\.palette) private var p
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(skoga: .check).skogaIconSize(14)
            Text(text)
                .font(SkogaFont.body(12.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.input).fill(p.ink)
        )
        .foregroundStyle(p.paper)
        .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 8)
    }
}
