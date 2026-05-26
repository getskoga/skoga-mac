import SwiftUI
import AppKit

struct MainWindow: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(RosterState.self) private var roster
    @Environment(ModalState.self) private var modal
    @Environment(DaemonClientHolder.self) private var daemon

    var body: some View {
        ZStack(alignment: .top) {
            // Background covers the whole window (under the hidden titlebar too).
            p.paper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TitleBar()
                DaemonStatusBanner(status: daemon.daemonStatus)
                HStack(spacing: 0) {
                    Sidebar()
                    mainArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            ZStack {
                if let toast = modal.toast {
                    VStack {
                        Spacer()
                        ToastView(text: toast).padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: modal.toast)

            if let id = modal.prAgentId, let agent = roster.agents.first(where: { $0.id == id }) {
                PRModal(agent: agent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let id = modal.stopAgentId, let agent = roster.agents.first(where: { $0.id == id }) {
                StopConfirmModal(agent: agent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if modal.commandPaletteOpen {
                CommandPalette()
                    .transition(.opacity)
            }
        }
        .onExitCommand { modal.commandPaletteOpen = false }
        .background(WindowAccessor(onWindow: { coordinator.registerMainWindow($0) }))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
            coordinator.setAppHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
            coordinator.setAppHidden(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { note in
            guard coordinator.isMainWindow(note.object) else { return }
            coordinator.setWindowMinimized(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { note in
            guard coordinator.isMainWindow(note.object) else { return }
            coordinator.setWindowMinimized(false)
        }
    }

    @ViewBuilder private var mainArea: some View {
        VStack(spacing: 0) {
            switch modal.view {
            case .roster:
                CockpitStrip()
                RosterView()
            case .conversation:
                if let agent = coordinator.openAgent {
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
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: modal.view)
    }

    @ViewBuilder private var placeholderView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(modal.view.rawValue.capitalized)
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
