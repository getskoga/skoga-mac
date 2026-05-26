import SwiftUI

/// Settings → Notifications · Mobile. Lays out the four cards from the
/// design (PDF p6, issue #21):
///
/// 1. **What wakes you** — the three "should this raise an alert?"
///    triggers (blocked / finished / budget). All default to on; the
///    blocked toggle is the contract for the "agent needs my decision"
///    banner the wired-notifications issue will fire.
/// 2. **Delivery** — desktop-banner master + sound-on-attention-only.
/// 3. **Mobile bridge** — Solo-tier "Coming soon" stub. The pairing /
///    forward / unblock-from-anywhere features ship later; per the
///    issue, v1 only needs an honest explainer so a Solo user knows
///    the roadmap, not a dead-end "coming soon" sticker.
/// 4. **Quiet hours** — toggle + start/end time range. Suppresses
///    banners *and* sound between the chosen times; audit-log entries
///    are still written (so a blocked agent still shows up in Roster).
///
/// Persistence: the issue specifies daemon `config.set` under
/// `skoga.notifications.*` (getskoga/skoga#95). That RPC isn't wired on
/// the Mac side yet, so for now toggles bind to `@AppStorage` keyed
/// under the same namespace — a future migration to the daemon is a
/// mechanical key-for-key swap and Roster/Cockpit can read the same
/// UserDefaults values today through `NotificationPrefs.read` without
/// re-routing through a daemon slice.
struct NotificationsSettingsSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            wakesYouCard
            deliveryCard
            mobileBridgeCard
            quietHoursCard
        }
    }

    // MARK: – Section header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.notifications.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.notifications.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("Decide what's worth pulling you back to Skoga — desktop banners now, iPhone bridge later.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Card 1: What wakes you

    private var wakesYouCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("WHAT WAKES YOU")
                    .padding(.bottom, 6)
                Text("Pick the moments that should raise a banner. Anything left off still writes to the audit log — Roster will surface it; macOS won't.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 14) {
                    NotificationToggleRow(
                        key: NotificationPrefs.Wake.blocked,
                        defaultValue: true,
                        icon: .alert,
                        title: "Agent is blocked",
                        subtitle: "Fires the moment a session goes to Waiting — it needs your decision before it can move."
                    )
                    NotificationToggleRow(
                        key: NotificationPrefs.Wake.finished,
                        defaultValue: true,
                        icon: .check,
                        title: "Agent finished a run",
                        subtitle: "Run ended cleanly and a PR is ready for review."
                    )
                    NotificationToggleRow(
                        key: NotificationPrefs.Wake.budget,
                        defaultValue: true,
                        icon: .bolt,
                        title: "Budget alert at 80% of daily cap",
                        subtitle: "One ping per day per cap. Silences itself until tomorrow's window rolls over."
                    )
                }
            }
        }
    }

    // MARK: – Card 2: Delivery

    private var deliveryCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("DELIVERY")
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 14) {
                    NotificationToggleRow(
                        key: NotificationPrefs.Delivery.banners,
                        defaultValue: true,
                        icon: .watch,
                        title: "Desktop banners",
                        subtitle: "Native macOS notifications. Posted through the system's banner stack so Do Not Disturb and Focus modes work as you'd expect."
                    )
                    NotificationToggleRow(
                        key: NotificationPrefs.Delivery.soundAttentionOnly,
                        defaultValue: true,
                        icon: .spark,
                        title: "Sound on attention-needed only",
                        subtitle: "Mutes the chime for finished-run and budget pings — only blocked-agent alerts make a sound."
                    )
                }
            }
        }
    }

    // MARK: – Card 3: Mobile bridge (Coming soon stub)

    private var mobileBridgeCard: some View {
        // Visually distinct from the live cards — paper (the panel's
        // own background tier) instead of paper2 reads as "below" the
        // live cards without inventing a new opacity step. Roadmap
        // bullets mirror PlaceholderSection's treatment so the
        // affordance reads "we're being specific about what's missing".
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SettingsCardLabel("MOBILE BRIDGE")
                Spacer()
                comingInSoloPill
            }

            Text("Pair an iPhone to forward attention-needed pings off your desk. The Mac-side notifications above ship first; the phone/watch bridge follows in the Solo tier.")
                .font(SkogaFont.body(12))
                .foregroundStyle(p.inkMute)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                bridgeBullet("Pair an iPhone via QR code")
                bridgeBullet("Forward attention-needed pings to phone or watch")
                bridgeBullet("\"Unblock from anywhere\" message bar — reply from your lock screen")
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    /// Filled amber pill — matches PlaceholderSection's "v1 roadmap"
    /// pill family rather than minting a one-off dusk variant. The
    /// `amberSoft` fill also brings the contrast above WCAG AA in dark
    /// mode where the border-only treatment was sub-3:1.
    private var comingInSoloPill: some View {
        Text("COMING IN SOLO")
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.8)
            .foregroundStyle(p.amber)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .fill(p.amberSoft.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .stroke(p.amber.opacity(0.45), lineWidth: Tokens.Hairline.width)
            )
    }

    private func bridgeBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                .fill(p.paper2)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(SkogaFont.body(12.5))
                .foregroundStyle(p.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: – Card 4: Quiet hours

    private var quietHoursCard: some View {
        SettingsCard {
            QuietHoursPanel()
        }
    }
}

// MARK: – AppStorage keys + read helper

/// Single source of truth for the `skoga.notifications.*` keys and
/// their default values. Lives outside the view so other surfaces
/// (Roster's blocked-banner, the future wired-notifications hook,
/// daemon-migration helper) can read the same names *and* the same
/// defaults — `AppStorage` only writes its default on first read, so
/// any caller that wants "is the blocked-toggle on?" before the user
/// has visited Settings must use `read(_:)` instead of querying
/// `UserDefaults.standard.bool(forKey:)` directly (which would return
/// `false` for an absent key).
enum NotificationPrefs {
    enum Wake {
        static let blocked  = "skoga.notifications.wake.blocked"
        static let finished = "skoga.notifications.wake.finished"
        static let budget   = "skoga.notifications.wake.budget"
    }
    enum Delivery {
        static let banners            = "skoga.notifications.delivery.banners"
        static let soundAttentionOnly = "skoga.notifications.delivery.soundAttentionOnly"
    }
    enum Quiet {
        static let enabled      = "skoga.notifications.quiet.enabled"
        /// Start/end stored as minutes-from-midnight (0..1439) so the
        /// values survive timezone shifts and can be compared with a
        /// plain integer compare. AppStorage doesn't support `Date`
        /// directly anyway.
        ///
        /// TODO: any consumer answering "are we quiet right now?" must
        /// handle wrap-around — when `end < start`, the window is
        /// `now >= start || now < end` (covers e.g. 22:00 → 07:00).
        static let startMinutes = "skoga.notifications.quiet.startMinutes"
        static let endMinutes   = "skoga.notifications.quiet.endMinutes"
    }

    /// Defaults for the boolean prefs. Mirrors the `defaultValue` each
    /// row passes to its `@AppStorage` — kept in one table so a row
    /// that's never been viewed still reports its true intended state
    /// to non-Settings callers.
    private static let boolDefaults: [String: Bool] = [
        Wake.blocked: true,
        Wake.finished: true,
        Wake.budget: true,
        Delivery.banners: true,
        Delivery.soundAttentionOnly: true,
        Quiet.enabled: false,
    ]

    /// Resolve the persisted bool, falling back to the canonical default
    /// when nothing has been written yet. Use this from anywhere outside
    /// the Settings panel; the panel itself uses `@AppStorage` so its
    /// rows stay reactive.
    static func read(_ key: String) -> Bool {
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            return stored
        }
        return boolDefaults[key] ?? false
    }
}

// MARK: – Toggle row

/// One row of: small neutral icon tile · title + subtitle · macOS
/// switch on the right. Icon tile uses the same paper3/ink2 treatment
/// as `ProviderCard`'s header so Settings stays visually consistent
/// across panels (no per-row accent invention).
private struct NotificationToggleRow: View {
    @Environment(\.palette) private var p
    let key: String
    let defaultValue: Bool
    let icon: SkogaIcon
    let title: String
    let subtitle: String

    @AppStorage private var on: Bool

    init(key: String, defaultValue: Bool, icon: SkogaIcon, title: String, subtitle: String) {
        self.key = key
        self.defaultValue = defaultValue
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._on = AppStorage(wrappedValue: defaultValue, key)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: icon).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(subtitle)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Cap the text column so the switch always has room on the
            // trailing edge even at the narrowest detail-pane width
            // (~720pt minus padding). Without this, a long subtitle
            // compressed the Toggle off-screen at compact widths.
            .frame(maxWidth: .infinity, alignment: .leading)

            // Title in the Toggle's label slot keeps the row accessible
            // — VoiceOver reads "Agent is blocked, switch, on" instead
            // of just "switch, on". `.labelsHidden()` keeps the visual
            // layout we already built above.
            Toggle(title, isOn: $on)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
        }
    }
}

// MARK: – Quiet hours panel

/// Wrapper around the quiet-hours toggle + time range. Owns the integer
/// minute storage and hands `Int` bindings to `CompactTimePicker` so
/// the picker doesn't have to know about the AppStorage layer.
private struct QuietHoursPanel: View {
    @Environment(\.palette) private var p

    @AppStorage(NotificationPrefs.Quiet.enabled) private var enabled: Bool = false
    /// Defaults: 22:00 → 07:00. Round numbers a user will recognize as
    /// "evening through morning" without having to think about it.
    @AppStorage(NotificationPrefs.Quiet.startMinutes) private var startMinutes: Int = 22 * 60
    @AppStorage(NotificationPrefs.Quiet.endMinutes)   private var endMinutes:   Int = 7 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, enabled ? 14 : 0)

            if enabled {
                pickerRow
                Text(rangeBlurb)
                    .font(SkogaFont.body(11.5))
                    .foregroundStyle(p.inkMute)
                    .padding(.top, 10)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .clock).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                SettingsCardLabel("QUIET HOURS")
                // Reads correctly in both on and off states — without
                // "When on" the row sounded like quiet hours were
                // already active even when the toggle was off.
                Text("When on, suppresses banners and sound between the chosen times. Audit-log entries still write — Roster surfaces what fired silently.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Quiet hours", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
        }
    }

    private var pickerRow: some View {
        HStack(spacing: 10) {
            timeField(label: "FROM", minutes: $startMinutes)
            Image(skoga: .chevron).skogaIconSize(10)
                .foregroundStyle(p.inkFaint)
            timeField(label: "TO", minutes: $endMinutes)
            Spacer()
        }
    }

    private func timeField(label: String, minutes: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.8)
                .foregroundStyle(p.inkFaint)

            CompactTimePicker(minutes: minutes)
                .accessibilityLabel(label == "FROM" ? "Quiet hours start" : "Quiet hours end")
        }
    }

    /// Friendly description that makes the wrap-around case ("22:00 to
    /// 07:00 next day") explicit — otherwise a user setting "22:00 to
    /// 07:00" might wonder whether quiet hours cover the wee hours or
    /// only the four minutes after 22:00.
    private var rangeBlurb: String {
        let s = Self.formatMinutes(startMinutes)
        let e = Self.formatMinutes(endMinutes)
        if startMinutes == endMinutes {
            return "Start and end are the same — quiet hours will never fire."
        }
        let wraps = endMinutes < startMinutes
        return wraps
            ? "Quiet from \(s) until \(e) the next morning."
            : "Quiet from \(s) until \(e) the same day."
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        // 24h format keeps the wrap-around sentence ("22:00 until 07:00
        // the next morning") readable without an AM/PM tag.
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: – Compact time picker

/// Hour:minute picker built from two `Menu`s so the palette stays
/// parchment-coherent — `DatePicker(.field)` would inject the system
/// blue accent next to our forest-tinted switches. Minute step is 5
/// (a 60-item menu would scroll); hour step is 1. If a non-step value
/// is stored, the displayed text is still accurate — picking a new
/// value snaps to the step.
private struct CompactTimePicker: View {
    @Environment(\.palette) private var p
    @Binding var minutes: Int

    private var hour: Int { minutes / 60 }
    private var minute: Int { minutes % 60 }

    private static let minuteSteps: [Int] = Array(stride(from: 0, to: 60, by: 5))

    var body: some View {
        HStack(spacing: 2) {
            menuField(displayed: hour, options: Array(0..<24), a11yLabel: "Hour") { newHour in
                minutes = newHour * 60 + minute
            }
            Text(":")
                .font(SkogaFont.mono(13))
                .foregroundStyle(p.inkFaint)
            menuField(displayed: minute, options: Self.minuteSteps, a11yLabel: "Minute") { newMinute in
                minutes = hour * 60 + newMinute
            }
        }
    }

    @ViewBuilder
    private func menuField(
        displayed: Int,
        options: [Int],
        a11yLabel: String,
        onPick: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { value in
                Button(String(format: "%02d", value)) { onPick(value) }
            }
        } label: {
            Text(String(format: "%02d", displayed))
                .font(SkogaFont.mono(13))
                .foregroundStyle(p.ink)
                .frame(minWidth: 22)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(p.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(a11yLabel)
    }
}
