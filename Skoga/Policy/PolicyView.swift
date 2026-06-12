import SwiftUI

/// Policy view — the containment denial review surface. Lists the
/// per-session accesses the daemon's sandbox/proxy refused and lets the
/// user widen the allowlist in one click instead of hand-editing
/// `config.toml`. Reads `coordinator.policy` (populated by the 5s
/// `refresh()` ride-along and the panel's own `loadDenials`) and renders
/// a card per denial with a scope picker; deny-floor entries render as
/// permanently blocked.
///
/// See getskoga/skoga-mac#109. Toolchain labels come from the daemon
/// (getskoga/skoga#164) — when present they replace the raw hostname so
/// the row reads "the npm registry" instead of "registry.npmjs.org".
struct PolicyView: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PolicyState.self) private var policy

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        // Single auto-load on first appearance. The ride-along poll in
        // refresh() keeps the list live afterward; this just owns the
        // initial loading/error affordance (and is a no-op flash-wise
        // when the poll already populated the list — see loadDenials).
        .task {
            await coordinator.loadDenials()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Denials")
                .font(SkogaFont.serifTitle(26))
                .foregroundStyle(p.ink)
            Text("Accesses the sandbox refused. Promote one to widen the allowlist — the agent's next attempt succeeds. Deny-floor rules are permanent.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.5)
                .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .background(p.paper)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var content: some View {
        // Outer guard on emptiness so a transient `.loading` during a
        // ride-along poll doesn't blow already-shown rows off screen.
        // Mirrors HistoryView's content gating.
        if policy.denials.isEmpty {
            switch policy.loadState {
            case .idle, .loading: loadingState
            case .error(let msg): errorState(message: msg)
            case .loaded:         emptyState
            }
        } else {
            list
        }
    }

    private var list: some View {
        // Floor entries sink to the bottom — they're informational, not
        // actionable, so the promotable denials that actually want the
        // user's attention sit up top. Within each group the daemon's
        // newest-first order is preserved.
        let rows = policy.denials.sorted { lhs, rhs in
            if lhs.floor != rhs.floor { return !lhs.floor }
            return lhs.denied_at > rhs.denied_at
        }
        return ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(rows) { denial in
                    DenialRow(
                        denial: denial,
                        promoting: policy.isPromoting(denial.id),
                        onPromote: { scope in
                            Task { await coordinator.promoteDenial(id: denial.id, scope: scope) }
                        }
                    )
                }
            }
            .padding(.horizontal, Tokens.Pad.viewX)
            .padding(.top, Tokens.Pad.viewY)
            .padding(.bottom, 28)
        }
        .background(p.paper)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.small)
            Text("Loading denials…")
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(skoga: .alert).skogaIconSize(20)
                .foregroundStyle(p.ember)
            Text("Couldn't load denials")
                .font(SkogaFont.bodyMedium(13))
                .foregroundStyle(p.ink)
            Text(message)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                Task { await coordinator.loadDenials() }
            } label: {
                Text("Retry")
                    .font(SkogaFont.smallMedium(11.5))
                    .padding(.horizontal, 14).frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper2)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
                    .foregroundStyle(p.ink2)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(skoga: .shield).skogaIconSize(22)
                .foregroundStyle(p.forest)
            Text("Nothing denied")
                .font(SkogaFont.bodyMedium(13))
                .foregroundStyle(p.ink)
            Text("Agents are working within the allowlist. Blocked accesses will show up here for review.")
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.inkMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }
}

// MARK: – Denial row

/// One denial card: kind chip + primary label (toolchain label when the
/// daemon supplied one, else the raw target), a secondary metadata line
/// (raw target · which agent · when · ×N), and a trailing control — a
/// scope picker for promotable denials, a "Blocked" pill for deny-floor
/// entries.
private struct DenialRow: View {
    @Environment(\.palette) private var p
    let denial: RPCDenial
    let promoting: Bool
    let onPromote: (PolicyPromoteScope) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            kindChip
            VStack(alignment: .leading, spacing: 3) {
                Text(primaryText)
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                metaLine
            }
            Spacer(minLength: 12)
            trailingControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.card)
        )
        .opacity(promoting ? 0.6 : 1)
    }

    /// Toolchain label wins; raw target is the fallback. When a label is
    /// present the raw target moves to the meta line so the user can
    /// still see exactly what was blocked.
    private var primaryText: String {
        denial.label ?? denial.target
    }

    private var kindChip: some View {
        Text(denial.kind.chipLabel)
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.6)
            .foregroundStyle(denial.floor ? p.ember : p.ink2)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .fill(denial.floor ? p.emberSoft.opacity(0.5) : p.paper4)
            )
            .fixedSize()
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            // Show the raw target only when the primary line is a label —
            // otherwise the primary line already *is* the target and
            // repeating it is noise.
            if denial.label != nil {
                Text(denial.target)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkMute)
                    .lineLimit(1)
                    .truncationMode(.middle)
                dot
            }
            if let session = denial.session_id {
                Text(NordicNames.displayName(forSessionId: session))
                    .font(SkogaFont.small(11))
                    .foregroundStyle(p.inkMute)
                dot
            }
            Text(relativeWhen(denial.denied_at))
                .font(SkogaFont.small(11))
                .foregroundStyle(p.inkFaint)
            if let n = denial.occurrences, n > 1 {
                Text("×\(n)")
                    .font(SkogaFont.monoTiny(9.5))
                    .foregroundStyle(p.inkMute)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(p.paper3)
                    )
            }
        }
    }

    private var dot: some View {
        Text("·").font(SkogaFont.small(11)).foregroundStyle(p.inkFaint)
    }

    @ViewBuilder private var trailingControl: some View {
        if denial.floor {
            // Deny-floor: permanent, not promotable. Render a muted
            // shield pill so the user understands this is policy, not a
            // missing affordance.
            HStack(spacing: 5) {
                Image(skoga: .shield).skogaIconSize(10)
                Text("Blocked")
                    .font(SkogaFont.smallMedium(11))
            }
            .foregroundStyle(p.ember)
            .padding(.horizontal, 10).frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.emberSoft.opacity(0.35))
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
            .help("Deny-floor rule — can't be promoted.")
        } else if promoting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Allowing…")
                    .font(SkogaFont.smallMedium(11))
                    .foregroundStyle(p.ink2)
            }
            .padding(.horizontal, 10).frame(height: 28)
        } else {
            scopePicker
        }
    }

    /// One-click promote with a scope picker (getskoga/skoga-mac#109).
    /// A `Menu` so the primary click reveals once / session / global in
    /// one gesture — project scope is deferred.
    private var scopePicker: some View {
        Menu {
            ForEach(PolicyPromoteScope.allCases, id: \.self) { scope in
                Button(scope.menuLabel) { onPromote(scope) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(skoga: .check).skogaIconSize(11)
                Text("Allow")
                    .font(SkogaFont.smallMedium(11.5))
            }
            .foregroundStyle(p.forestDeep)
            .padding(.horizontal, 12).frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(p.forestSoft.opacity(0.5))
                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Compact relative-time label for the denial timestamp, matching the
    /// terse style of the Agent card's `runtime` ("2m ago", "3h ago").
    private func relativeWhen(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }
}
