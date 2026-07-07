import Foundation
import SwiftUI

/// Settings → Privacy & data. Two destructive escape hatches (reset
/// first-run state, wipe `~/.skoga/`), the telemetry opt-out, and the
/// privacy policy link. Destructive actions go through a confirmation
/// dialog — accidentally clicking "Clear local state" deletes the
/// daemon's socket, agent worktrees, and credentials, which isn't
/// recoverable from a misclick.
struct PrivacySettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL
    @Environment(OnboardingState.self) private var onboarding
    @Environment(ModalState.self) private var modal
    @Environment(DaemonClientHolder.self) private var daemon

    @State private var confirmingClearLocal = false
    @State private var confirmingResetFirstRun = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            telemetryCard
            firstRunCard
            clearLocalCard
            privacyPolicyCard
        }
        .confirmationDialog(
            "Reset first-run state?",
            isPresented: $confirmingResetFirstRun,
            titleVisibility: .visible
        ) {
            Button("Reset first-run", role: .destructive) {
                onboarding.resetFirstRun()
                modal.showToast("First-run state cleared. Restart to see the wizard.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wipes the saved wizard picks (default model, workspace) and reopens the welcome card. Your daemon state and worktrees are untouched.")
        }
        .confirmationDialog(
            "Clear local Skoga state?",
            isPresented: $confirmingClearLocal,
            titleVisibility: .visible
        ) {
            Button("Clear ~/.skoga/", role: .destructive) {
                let result = LocalStateWiper.wipe()
                switch result {
                case .wiped:
                    modal.showToast("Cleared local Skoga state. Quit and relaunch Skoga to recreate it.")
                case .nothingToDo:
                    modal.showToast("Nothing to clear — ~/.skoga/ wasn't there.")
                case .failed(let message):
                    modal.showToast("Couldn't clear: \(message)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Mock-mode reminder: the on-screen daemon is seeded data,
            // but `~/.skoga/` on disk belongs to whichever real install
            // the developer has. Clearing here still nukes that real
            // install's state — surface the warning so a SKOGA_USE_MOCK
            // session doesn't accidentally wipe a working setup.
            Text(daemon.isMock
                 ? "Mock mode is on, but this still deletes the on-disk ~/.skoga/ — including any real install's daemon socket, agent worktrees, conversation transcripts, and cached credentials. Skoga can't recover that state. Quit and relaunch to recreate the directory."
                 : "Deletes ~/.skoga/, including the daemon socket, agent worktrees, conversation transcripts, and any cached credentials. The daemon will stop; quit and relaunch Skoga to recreate the directory.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.privacy.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.privacy.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text(SettingsSectionID.privacy.blurb)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Telemetry

    /// Telemetry is opt-in. Skoga doesn't currently emit anything beyond
    /// uncaught-crash reports, but persisting the user's choice now means
    /// any future telemetry can honor it without prompting again — and
    /// the privacy panel doesn't have to grow a new control when it
    /// lands.
    private var telemetryCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("TELEMETRY")
                    .padding(.bottom, 14)
                TelemetryToggleRow()
            }
        }
    }

    private var firstRunCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCardLabel("FIRST-RUN STATE")

                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                        Image(skoga: .loop).skogaIconSize(13).foregroundStyle(p.ink2)
                    }
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset first-run state")
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text("Drops your saved wizard picks and reopens onboarding from the welcome card. About → Re-run onboarding keeps them.")
                            .font(SkogaFont.body(12))
                            .foregroundStyle(p.inkMute)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            confirmingResetFirstRun = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(skoga: .loop).skogaIconSize(11)
                                Text("Reset first-run").font(SkogaFont.bodyMedium(12))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .foregroundStyle(p.ink2)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                    .fill(p.paper)
                                    .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var clearLocalCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    SettingsCardLabel("LOCAL STATE")
                    Spacer()
                    destructivePill
                }

                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(p.emberSoft.opacity(0.55))
                        Image(skoga: .alert).skogaIconSize(13).foregroundStyle(p.ember)
                    }
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.ember.opacity(0.5), lineWidth: Tokens.Hairline.width)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear ~/.skoga/")
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text("Deletes the daemon socket, agent worktrees, conversation transcripts, and cached credentials. The daemon will stop. Skoga can't recover the deleted state — use this when you want a clean reinstall.")
                            .font(SkogaFont.body(12))
                            .foregroundStyle(p.inkMute)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            confirmingClearLocal = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(skoga: .alert).skogaIconSize(11)
                                Text("Clear local state").font(SkogaFont.bodyMedium(12))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                    .fill(p.ember)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var destructivePill: some View {
        Text("DESTRUCTIVE")
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.8)
            .foregroundStyle(p.ember)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .fill(p.emberSoft.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .stroke(p.ember.opacity(0.45), lineWidth: Tokens.Hairline.width)
            )
    }

    private var privacyPolicyCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: .shield).skogaIconSize(13).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy Policy")
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text("What data Skoga collects, where it goes, and how to ask for it to be erased. Hosted on getskoga.dev — opens in your browser.")
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: "https://getskoga.dev/privacy") {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(skoga: .doc).skogaIconSize(11)
                            Text("Open privacy policy").font(SkogaFont.bodyMedium(12))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .foregroundStyle(p.ink2)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                .fill(p.paper)
                                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: – Telemetry toggle

/// Same row shape used by `NotificationsSettingsSection` so the
/// Settings panels stay visually consistent. The persisted key is
/// `skoga.privacy.telemetryEnabled`; consumers (none yet) should
/// always read through `PrivacyPrefs.telemetryEnabled` so the canonical
/// default (off) wins when the key hasn't been written.
private struct TelemetryToggleRow: View {
    @Environment(\.palette) private var p

    @AppStorage(PrivacyPrefs.telemetryEnabled) private var on: Bool = PrivacyPrefs.telemetryEnabledDefault

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .spark).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Share anonymous crash + error reports")
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(on
                     ? "Skoga will report uncaught exceptions and protocol errors with no personally identifying info. Off until you flip this — nothing is collected today."
                     : "Off. Skoga doesn't send anything off your machine — flip this on if you'd like to help us debug crashes you hit.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Telemetry", isOn: $on)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
        }
    }
}

// MARK: – AppStorage keys + read helpers

/// Single source of truth for the `skoga.privacy.*` keys + their
/// defaults. Same shape as `NotificationPrefs` / `BudgetPrefs` so a
/// non-Settings consumer (the crash reporter when it lands) can
/// resolve the canonical default for an absent key without re-querying
/// `UserDefaults` itself.
enum PrivacyPrefs {
    static let telemetryEnabled = "skoga.privacy.telemetryEnabled"
    /// Default off — opt-in. Flipping this default would silently
    /// re-enable telemetry for users who had explicitly turned it off
    /// on a prior install, so leave it pinned.
    static let telemetryEnabledDefault: Bool = false

    static func readTelemetryEnabled() -> Bool {
        if let v = UserDefaults.standard.object(forKey: telemetryEnabled) as? Bool { return v }
        return telemetryEnabledDefault
    }
}

// MARK: – Local state wiper

/// Outcome of attempting to wipe `~/.skoga/`. Distinct cases so the
/// Settings panel can route each to the right toast — `nothingToDo`
/// means the directory was already absent, which is a benign success.
enum LocalStateWipeResult: Equatable {
    case wiped
    case nothingToDo
    case failed(String)
}

/// Wipes `~/.skoga/`. Used by Settings → Privacy → "Clear local state"
/// after the user confirms. Pure function over `FileManager` so the
/// view stays declarative and the operation is testable end-to-end.
///
/// Behavior choices worth flagging:
/// - The wipe is `removeItem` on the resolved directory, not a per-file
///   loop. The intent is "fresh install" — leaving a stray `daemon.log`
///   or `.sock` behind would defeat the point.
/// - `~/.skoga` is resolved via `FileManager.homeDirectoryForCurrentUser`
///   (not `NSString.expandingTildeInPath` against the literal `~/.skoga`)
///   so the path matches what the daemon writes from any sandbox
///   relocation.
/// - The daemon socket lives inside the wiped tree, so the daemon will
///   exit on its next socket op. We don't try to gracefully stop it —
///   the user explicitly asked for a teardown, and waiting on a daemon
///   that may already be unhealthy would just stall the dialog.
enum LocalStateWiper {
    @discardableResult
    static func wipe() -> LocalStateWipeResult {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".skoga", isDirectory: true)
        guard fm.fileExists(atPath: dir.path) else { return .nothingToDo }
        do {
            try fm.removeItem(at: dir)
            return .wiped
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
