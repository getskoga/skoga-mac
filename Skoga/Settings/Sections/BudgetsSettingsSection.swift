import SwiftUI

/// Settings → Budgets. Maps to PDF p7 / issue #22:
///
/// 1. **Spend caps** — a master "enforce caps" toggle, three numeric
///    dollar fields (per-run / daily / monthly), the "soft stop on cap"
///    toggle, and the alert-at threshold (50/75/80/100%). The master
///    toggle dims the three fields and the behavior card when off so
///    the daemon never stops a run, but usage still totals here and in
///    Cockpit.
/// 2. **Today (live)** — current spend, daily cap, and percent consumed.
///    Pulled from `RosterState.spend` (the same source the Cockpit
///    strip's "Spend" instrument reads) so the panel and the chrome
///    can't disagree. When the daemon ships `cockpit.spend_today`
///    (getskoga/skoga#86) the roster slice will start hydrating from
///    there; this view will follow without a UI change.
///
/// Persistence: the issue specifies daemon `config.set` under
/// `skoga.budgets.*` (getskoga/skoga#88). That RPC isn't wired on the
/// Mac side yet, so for now the controls bind to `@AppStorage` keyed
/// under the same namespace — a future migration to the daemon is a
/// mechanical key-for-key swap and other surfaces (Cockpit, future
/// enforcer) can read the same defaults today through `BudgetPrefs.read*`
/// without re-routing through a daemon slice.
struct BudgetsSettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(RosterState.self) private var roster

    /// Master gate for cap enforcement. When off, the three dollar
    /// fields and the behavior card still show their saved values
    /// (so toggling back on restores intent) but render dimmed and
    /// non-interactive, and the "Today" panel drops its progress bar.
    @AppStorage(BudgetPrefs.Behavior.capsEnabled) private var capsEnabled: Bool = BudgetPrefs.Behavior.capsEnabledDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            spendCapsCard
            behaviorCard
            todayCard
        }
    }

    // MARK: – Section header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.budgets.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.budgets.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("Caps that keep a runaway agent from running up your bill. Numbers here are dollar ceilings the daemon enforces; \"Today\" mirrors what Cockpit's spend instrument shows.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Card 1: Spend caps (master toggle + three numeric inputs)

    private var spendCapsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("SPEND CAPS")
                    .padding(.bottom, 14)

                EnforceCapsRow()
                    .padding(.bottom, 14)

                Hairline()
                    .padding(.bottom, 14)

                Text("Three ceilings, applied independently. Whichever you trip first wins — a $5 per-run cap stops a single session even if your daily and monthly budgets still have room.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                    .opacity(capsEnabled ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 22) {
                    DollarCapInput(
                        key: BudgetPrefs.Cap.perRun,
                        defaultValue: BudgetPrefs.Cap.perRunDefault,
                        suggestedRange: 1...20,
                        icon: .bolt,
                        title: "Per-run cap",
                        subtitle: "Stops a single session once it crosses this number.",
                        enabled: capsEnabled
                    )
                    DollarCapInput(
                        key: BudgetPrefs.Cap.daily,
                        defaultValue: BudgetPrefs.Cap.dailyDefault,
                        suggestedRange: 5...200,
                        icon: .clock,
                        title: "Daily cap",
                        subtitle: "Cumulative spend across every session in a calendar day.",
                        enabled: capsEnabled
                    )
                    DollarCapInput(
                        key: BudgetPrefs.Cap.monthly,
                        defaultValue: BudgetPrefs.Cap.monthlyDefault,
                        suggestedRange: 100...3000,
                        icon: .doc,
                        title: "Monthly cap",
                        subtitle: "Rolling 30-day total. Resets at the start of each calendar month.",
                        enabled: capsEnabled
                    )
                }
            }
        }
    }

    // MARK: – Card 2: Behavior on cap (soft stop + alert threshold)

    private var behaviorCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("WHEN A CAP IS HIT")
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 18) {
                    SoftStopRow()
                    Hairline()
                    AlertThresholdRow()
                }
            }
        }
        // Behavior is meaningless when no cap can trip — dim and lock
        // the whole card rather than leaving controls hot but inert.
        .opacity(capsEnabled ? 1 : 0.5)
        .disabled(!capsEnabled)
    }

    // MARK: – Card 3: Today (live)

    /// Live readout against the daily cap. We pull the current spend
    /// from `RosterState.spend.today` rather than re-querying — the
    /// roster slice is the canonical client-side cost source and reads
    /// from the same agent cost field Cockpit uses.
    private var todayCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SettingsCardLabel("TODAY")
                    Text("LIVE")
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.8)
                        .foregroundStyle(p.forestDeep)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                .fill(p.forestSoft.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                .stroke(p.forest.opacity(0.45), lineWidth: Tokens.Hairline.width)
                        )
                    Spacer()
                }
                .padding(.bottom, 14)

                TodaySpendPanel()
            }
        }
    }
}

// MARK: – AppStorage keys + read helpers

/// Single source of truth for the `skoga.budgets.*` keys and their
/// default values. Lives outside the view so other surfaces (Cockpit's
/// spend instrument, the future cap enforcer, daemon-migration helper)
/// can read the same names *and* the same defaults — `AppStorage` only
/// writes its default on first read, so any caller that wants "what's
/// the daily cap?" before the user has visited Settings must use the
/// `read*` helpers rather than querying `UserDefaults` directly (which
/// would return 0 for an absent key).
enum BudgetPrefs {
    enum Cap {
        static let perRun  = "skoga.budgets.cap.perRun"
        static let daily   = "skoga.budgets.cap.daily"
        static let monthly = "skoga.budgets.cap.monthly"

        // Canonical defaults — every call site (per-row AppStorage,
        // the read-helper lookup table, the Today panel's mirror of
        // the daily cap) pulls from here so they can't drift.
        static let perRunDefault:  Double = 5
        static let dailyDefault:   Double = 40
        static let monthlyDefault: Double = 800
    }
    enum Behavior {
        static let capsEnabled           = "skoga.budgets.behavior.capsEnabled"
        static let softStop              = "skoga.budgets.behavior.softStop"
        static let alertThresholdPercent = "skoga.budgets.behavior.alertThresholdPercent"

        static let capsEnabledDefault:           Bool = true
        static let softStopDefault:              Bool = true
        static let alertThresholdPercentDefault: Int  = 80
    }

    private static let doubleDefaults: [String: Double] = [
        Cap.perRun:  Cap.perRunDefault,
        Cap.daily:   Cap.dailyDefault,
        Cap.monthly: Cap.monthlyDefault,
    ]

    private static let intDefaults: [String: Int] = [
        Behavior.alertThresholdPercent: Behavior.alertThresholdPercentDefault,
    ]

    private static let boolDefaults: [String: Bool] = [
        Behavior.capsEnabled: Behavior.capsEnabledDefault,
        Behavior.softStop:    Behavior.softStopDefault,
    ]

    /// Discrete alert-threshold steps the issue calls out. Centralized
    /// so the picker and any future "did we cross a threshold?" check
    /// agree on the set.
    static let alertThresholdSteps: [Int] = [50, 75, 80, 100]

    static func readDouble(_ key: String) -> Double {
        if let v = UserDefaults.standard.object(forKey: key) as? Double { return v }
        return doubleDefaults[key] ?? 0
    }

    static func readInt(_ key: String) -> Int {
        if let v = UserDefaults.standard.object(forKey: key) as? Int { return v }
        return intDefaults[key] ?? 0
    }

    static func readBool(_ key: String) -> Bool {
        if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
        return boolDefaults[key] ?? false
    }
}

// MARK: – Dollar cap input row

/// One cap row: icon tile + title/subtitle on the left, a numeric
/// dollar field on the right. We dropped the slider — a fixed track
/// either pinches users who want $5,000 monthly caps or wastes
/// resolution on users who want $20. Typing a number is direct and
/// uncapped; `suggestedRange` only feeds the "Typical" hint below.
private struct DollarCapInput: View {
    @Environment(\.palette) private var p
    let key: String
    let defaultValue: Double
    let suggestedRange: ClosedRange<Double>
    let icon: SkogaIcon
    let title: String
    let subtitle: String
    let enabled: Bool

    @AppStorage private var value: Double
    @FocusState private var focused: Bool

    init(
        key: String,
        defaultValue: Double,
        suggestedRange: ClosedRange<Double>,
        icon: SkogaIcon,
        title: String,
        subtitle: String,
        enabled: Bool
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.suggestedRange = suggestedRange
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.enabled = enabled
        self._value = AppStorage(wrappedValue: defaultValue, key)
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

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text(subtitle)
                            .font(SkogaFont.body(12))
                            .foregroundStyle(p.inkMute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    dollarField
                }
                Text("Typical: \(formatDollars(suggestedRange.lowerBound))–\(formatDollars(suggestedRange.upperBound))")
                    .font(SkogaFont.monoTiny(9.5))
                    .foregroundStyle(p.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }

    /// `$` glyph sits in the chrome (not in the editable text) so the
    /// user can't delete it. `.number.precision(.fractionLength(0))`
    /// keeps the typed value whole-dollar — `AppStorage` still stores
    /// a `Double`, which matches what every consumer reads.
    @ViewBuilder private var dollarField: some View {
        HStack(spacing: 1) {
            Text("$")
                .font(SkogaFont.serifValue(20))
                .foregroundStyle(p.ink2)
            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(SkogaFont.serifValue(20))
                .foregroundStyle(p.ink)
                .monospacedDigit()
                .frame(width: 64)
                .focused($focused)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .fill(p.paper3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .stroke(focused ? p.forest : p.rule, lineWidth: Tokens.Hairline.width)
        )
        .accessibilityLabel(title)
        .accessibilityValue(formatDollars(value))
    }

    /// Whole dollars (no cents) — the field's formatter trims to
    /// integer precision, and the "Typical" hint should match.
    private func formatDollars(_ v: Double) -> String {
        "$\(Int(v.rounded()))"
    }
}

// MARK: – Enforce caps master toggle

/// Master switch that gates the three cap fields and the behavior card.
/// Off = the daemon never stops a run for spend; we still tally usage
/// in the "Today" panel and in Cockpit/Telemetry, but no cap can trip.
private struct EnforceCapsRow: View {
    @Environment(\.palette) private var p

    @AppStorage(BudgetPrefs.Behavior.capsEnabled) private var enabled: Bool = BudgetPrefs.Behavior.capsEnabledDefault

    var body: some View {
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

            VStack(alignment: .leading, spacing: 2) {
                Text("Enforce caps")
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                // Spell out the off-state so flipping the switch doesn't
                // feel like a quiet defaults change — the user is opting
                // out of a safety rail.
                Text(enabled
                     ? "Stop or pause a run when it crosses one of the limits below."
                     : "Caps are off — runs are never stopped, but spend is still tracked.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Enforce caps", isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
        }
    }
}

// MARK: – Soft stop toggle row

/// "Soft stop on cap" toggle. Same layout primitives as the toggle rows
/// in `NotificationsSettingsSection` so the two cards read as one
/// family — same tile size, same title/subtitle treatment, same switch
/// tint.
private struct SoftStopRow: View {
    @Environment(\.palette) private var p

    @AppStorage(BudgetPrefs.Behavior.softStop) private var softStop: Bool = BudgetPrefs.Behavior.softStopDefault

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .check).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Soft stop on cap")
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                // Two-state description so the row reads correctly in
                // either position. Off = hard kill is the call-out from
                // the issue — surfacing it inline keeps the toggle from
                // feeling like a quiet defaults change.
                Text(softStop
                     ? "Finish the current step, then pause and ask before continuing."
                     : "Hard kill — the run is terminated mid-step the moment a cap trips.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Soft stop on cap", isOn: $softStop)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(p.forest)
                .controlSize(.small)
        }
    }
}

// MARK: – Alert threshold row

/// "Alert me at X%" — discrete steps from the issue (50/75/80/100). Rendered
/// as a segmented selector so the four options are visible without a
/// menu open, and so a click lands without a slider's drag-precision
/// problem on four buckets.
private struct AlertThresholdRow: View {
    @Environment(\.palette) private var p

    @AppStorage(BudgetPrefs.Behavior.alertThresholdPercent) private var percent: Int = BudgetPrefs.Behavior.alertThresholdPercentDefault

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .alert).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alert me at")
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text("Pings the OS notification once per day per cap. Honors the Notifications panel's quiet hours and \"budget alerts\" toggle.")
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(BudgetPrefs.alertThresholdSteps, id: \.self) { step in
                        AlertStepChip(value: step, selected: percent == step) {
                            percent = step
                        }
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One pill in the alert-threshold selector. Selected pill takes the
/// forest fill the rest of Settings uses for "this is the active
/// choice"; the rest stay in the paper/rule family so the row reads as
/// a single control, not four competing CTAs.
private struct AlertStepChip: View {
    @Environment(\.palette) private var p
    let value: Int
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(value)%")
                .font(SkogaFont.bodyMedium(12))
                .foregroundStyle(selected ? .white : p.ink2)
                .frame(minWidth: 44)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(selected ? p.forest : (hovering ? p.paper3 : p.paper))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .stroke(selected ? .clear : p.rule, lineWidth: Tokens.Hairline.width)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(value) percent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: – Today (live) panel

/// Reads `RosterState.spend.today` and compares against the user's
/// daily cap. Renders the dollar headline, an inline cap callout, and a
/// progress bar that switches accent based on which threshold band the
/// user is in. The same forest → amber → ember progression Cockpit
/// would use if Spend were ever tinted by load.
private struct TodaySpendPanel: View {
    @Environment(\.palette) private var p
    @Environment(RosterState.self) private var roster

    @AppStorage(BudgetPrefs.Behavior.capsEnabled) private var capsEnabled: Bool = BudgetPrefs.Behavior.capsEnabledDefault
    @AppStorage(BudgetPrefs.Cap.daily) private var dailyCap: Double = BudgetPrefs.Cap.dailyDefault
    @AppStorage(BudgetPrefs.Behavior.alertThresholdPercent) private var alertPercent: Int = BudgetPrefs.Behavior.alertThresholdPercentDefault

    private var today: Double { roster.spend.today }
    /// Guard against a zero cap (someone setting `$5` and bumping it to
    /// `$0` via direct UserDefaults write) — division by zero on a
    /// percent would put `NaN` on screen. Treat caps-off or <= 0 as
    /// "no cap" so the same render path catches both.
    private var pct: Double {
        guard capsEnabled, dailyCap > 0 else { return 0 }
        return min(max(today / dailyCap, 0), 1)
    }
    private var pctInt: Int { Int((pct * 100).rounded()) }

    private var barColor: Color {
        if !capsEnabled { return p.inkMute }
        if pctInt >= 100 { return p.ember }
        if pctInt >= alertPercent { return p.amber }
        return p.forest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formatDollars(today))
                    .font(SkogaFont.serifValue(28))
                    .foregroundStyle(p.ink)
                    .monospacedDigit()
                Text(capsEnabled ? "of \(formatDollars(dailyCap)) daily cap" : "tracked · caps off")
                    .font(SkogaFont.monoSmall(11))
                    .foregroundStyle(p.inkMute)
                Spacer()
                if capsEnabled {
                    Text("\(pctInt)%")
                        .font(SkogaFont.mono(12))
                        .foregroundStyle(barColor)
                        .monospacedDigit()
                }
            }

            // Hide the meter outright when caps are off — there's no
            // ceiling to render against, and a flat-empty bar would
            // read as "you've spent $0" instead of "tracking only".
            if capsEnabled {
                BudgetBar(progress: pct, color: barColor)
            }

            // Footnote rotates between three messages depending on the
            // band, so the panel reads like a status line rather than a
            // bare meter. Same band logic as `barColor` to avoid drift.
            Text(footnote)
                .font(SkogaFont.body(11.5))
                .foregroundStyle(p.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        if !capsEnabled {
            return "Enforcement is off. Today's spend is still totalled here and in Cockpit, but no run will be stopped."
        }
        if dailyCap <= 0 {
            return "Daily cap isn't set. Enter a number above to enable enforcement."
        }
        if pctInt >= 100 {
            return "Daily cap exceeded. New runs will \(BudgetPrefs.readBool(BudgetPrefs.Behavior.softStop) ? "pause and ask before continuing" : "be killed immediately")."
        }
        if pctInt >= alertPercent {
            // Don't claim a notification fired — the daemon-side
            // wired-budget-alert hook (getskoga/skoga#86) isn't in this
            // build yet, and Notifications panel's `wake.budget` toggle
            // is the gate when it lands.
            return "Past your \(alertPercent)% alert threshold for the day."
        }
        return "Resets at midnight local time. Cockpit's spend instrument reads the same number."
    }

    private func formatDollars(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }
}

/// Thin progress bar with a paper track and a colored fill. Avoids the
/// stock `ProgressView` because its default look (blue, rounded with a
/// hard left edge regardless of progress) doesn't match the rest of
/// Settings.
private struct BudgetBar: View {
    @Environment(\.palette) private var p
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(p.paper3)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    // Render a 6pt sliver of fill when progress > 0 so a
                    // $0.01 spend doesn't appear as a flat-zero bar.
                    // Gate on `geo.size.width > 0` too — the first frame
                    // before layout measures would otherwise paint a 6pt
                    // sliver at progress == 0 and flash.
                    .frame(width: (progress > 0 && geo.size.width > 0)
                                  ? max(6, geo.size.width * progress)
                                  : 0)
                    .animation(.easeOut(duration: 0.25), value: progress)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
            )
        }
        .frame(height: 8)
    }
}
