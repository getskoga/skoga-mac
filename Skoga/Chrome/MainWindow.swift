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
        }
        .background(WindowAccessor())
        .animation(.easeOut(duration: 0.2), value: state.toast)
        .animation(.easeOut(duration: 0.15), value: state.view)
    }

    @ViewBuilder private var mainArea: some View {
        VStack(spacing: 0) {
            // Cockpit appears on roster (and would on review/telemetry/dispatch
            // if we mirrored the React conditional). For the slice, roster only.
            if state.view == .roster {
                CockpitStrip()
                RosterView()
            } else {
                placeholderView
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
