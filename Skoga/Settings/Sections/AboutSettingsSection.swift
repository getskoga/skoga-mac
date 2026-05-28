import SwiftUI

/// Settings → About. Real version / build / daemon-protocol fields
/// (resolved from `Bundle.main` and the daemon's `daemon.version` RPC
/// response cached on `DaemonClientHolder`), plus the issue's
/// supporting blocks: an updates row, links, acknowledgements, and the
/// hidden re-run first-run entry surfaced under About so users (and
/// QA) can retrigger the wizard after completion or skip.
struct AboutSettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL
    @Environment(DaemonClientHolder.self) private var daemon
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            versionsCard
            updatesCard
            linksCard
            acknowledgementsCard
            rerunCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.about.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.about.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text(SettingsSectionID.about.blurb)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Versions

    private var versionsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("VERSION")
                    .padding(.bottom, 14)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skoga")
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text(appVersionLine)
                            .font(SkogaFont.mono(11.5))
                            .foregroundStyle(p.inkMute)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.bottom, 14)

                Hairline()
                    .padding(.bottom, 14)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skoga daemon")
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text(daemonVersionLine)
                            .font(SkogaFont.mono(11.5))
                            .foregroundStyle(p.inkMute)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    DaemonReachabilityPill(status: daemon.daemonStatus)
                }
            }
        }
    }

    /// "0.0.1 (build 1)". `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
    /// come straight from xcodegen. Empty-string fallbacks keep the row
    /// from showing "Unknown · (build )" on an unsigned dev build that
    /// dropped one of the keys.
    private var appVersionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        switch (short.isEmpty, build.isEmpty) {
        case (false, false): return "\(short) (build \(build))"
        case (false, true):  return short
        case (true, false):  return "build \(build)"
        case (true, true):   return "unknown"
        }
    }

    private var daemonVersionLine: String {
        switch daemon.daemonStatus {
        case .connected(let version): return version
        case .mock:                   return "mock — running with seeded data"
        case .connecting:             return "Resolving — bootstrap in flight"
        case .notRunning(let detail): return "Not reachable · \(detail)"
        }
    }

    // MARK: – Updates

    /// Sparkle isn't bundled yet — the Mac app ships through a manual
    /// release artifact while we sort out signing. Until then the row
    /// is an explicit "open the releases page" affordance rather than
    /// a fake "Check for updates" that doesn't do anything, so the user
    /// can compare their local version against the latest tag without
    /// guessing where to look.
    private var updatesCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: .push).skogaIconSize(13).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check for updates")
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text("Sparkle auto-update isn't wired into this build. Open the releases page to compare your version against the latest tag — drag the new .app into Applications to install.")
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: "https://github.com/getskoga/skoga-mac/releases") {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(skoga: .doc).skogaIconSize(11)
                            Text("Open releases on GitHub").font(SkogaFont.bodyMedium(12))
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

    // MARK: – Links

    private var linksCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("LINKS")
                    .padding(.bottom, 8)

                ForEach(AboutLink.all) { link in
                    AboutLinkRow(link: link) {
                        if let url = URL(string: link.url) { openURL(url) }
                    }
                    if link.id != AboutLink.all.last?.id {
                        Hairline().padding(.leading, 40)
                    }
                }
            }
        }
    }

    // MARK: – Acknowledgements

    /// Bundled licenses we have to surface. The list is short on purpose
    /// — we ship the design's two font families and a single SwiftPM
    /// dependency. When more land, append to `Acknowledgement.all`; the
    /// card auto-grows.
    private var acknowledgementsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsCardLabel("ACKNOWLEDGEMENTS")
                    .padding(.bottom, 6)
                Text("Skoga ships these components. Each is open source under the license shown — click through for the full text.")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Acknowledgement.all) { item in
                        AcknowledgementRow(item: item) {
                            if let url = URL(string: item.licenseUrl) { openURL(url) }
                        }
                    }
                }
            }
        }
    }

    // MARK: – Re-run first-run wizard

    /// Hidden re-run entry. Visible from About but not promoted in the
    /// sidebar — its purpose is to give the user (and QA) a way to
    /// retrigger the wizard after they completed or skipped midway, per
    /// the issue's "hidden Settings · About entry for testing" note.
    private var rerunCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsCardLabel("FIRST-RUN WIZARD")

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
                        Text("Re-run onboarding")
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text("Drops you back on the welcome card with your previous picks (default model, sandbox carveouts, workspace, etc.) pre-filled.")
                            .font(SkogaFont.body(12))
                            .foregroundStyle(p.inkMute)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            onboarding.restart()
                        } label: {
                            HStack(spacing: 6) {
                                Image(skoga: .loop).skogaIconSize(11)
                                Text("Re-run first-run").font(SkogaFont.bodyMedium(12))
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
}

// MARK: – Daemon reachability pill

/// Small status pill mirroring `DaemonStatusBanner`'s vocabulary —
/// keeps the About panel honest about whether the daemon version we
/// just printed is fresh or stale. Doesn't render a CTA itself; the
/// banner on `MainWindow` is the place that surfaces the restart hint.
private struct DaemonReachabilityPill: View {
    @Environment(\.palette) private var p
    let status: DaemonStatus

    var body: some View {
        let (label, fg, bg) = palette
        Text(label)
            .font(SkogaFont.monoTiny(9.5))
            .tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .fill(bg.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                    .stroke(fg.opacity(0.45), lineWidth: Tokens.Hairline.width)
            )
    }

    private var palette: (String, Color, Color) {
        // `inkMute` on `paper3` for `.connecting` reads as a flat-grey
        // neutral, but the `.opacity(0.55)` fade on the fill below
        // dropped that combination below ~3:1 in light mode. Use the
        // amber family the same way Notifications does for `MOCK` —
        // "in flight" reads better as warm-yellow than pale-grey
        // anyway.
        switch status {
        case .connected: ("CONNECTED",   p.forestDeep, p.forestSoft)
        case .mock:      ("MOCK",        p.amber,      p.amberSoft)
        case .connecting:("CONNECTING",  p.amber,      p.amberSoft)
        case .notRunning:("NOT RUNNING", p.ember,      p.emberSoft)
        }
    }
}

// MARK: – Links table

struct AboutLink: Identifiable, Hashable {
    let id: String
    let label: String
    let subtitle: String
    let url: String
    let icon: SkogaIcon

    static let all: [AboutLink] = [
        .init(
            id: "website",
            label: "Website",
            subtitle: "getskoga.dev",
            url: "https://getskoga.dev",
            icon: .spark
        ),
        .init(
            id: "docs",
            label: "Documentation",
            subtitle: "Guides for dispatch, review, and the CLI",
            url: "https://getskoga.dev/docs",
            icon: .doc
        ),
        .init(
            id: "support",
            label: "Support",
            subtitle: "File an issue on the skoga-mac tracker",
            url: "https://github.com/getskoga/skoga-mac/issues",
            icon: .alert
        ),
        .init(
            id: "license",
            label: "License terms",
            subtitle: "The license under which Skoga ships",
            url: "https://getskoga.dev/license",
            icon: .shield
        ),
    ]
}

private struct AboutLinkRow: View {
    @Environment(\.palette) private var p
    let link: AboutLink
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(p.paper3)
                    Image(skoga: link.icon).skogaIconSize(12).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(link.label)
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text(link.subtitle)
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(skoga: .chevron).skogaIconSize(11).foregroundStyle(p.inkFaint)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering ? p.paper3 : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Open \(link.label)")
    }
}

// MARK: – Acknowledgements

struct Acknowledgement: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let license: String
    let licenseUrl: String

    static let all: [Acknowledgement] = [
        .init(
            id: "swiftterm",
            name: "SwiftTerm",
            blurb: "Terminal emulator powering the embedded Conversation pane.",
            license: "MIT",
            licenseUrl: "https://github.com/migueldeicaza/SwiftTerm/blob/main/LICENSE"
        ),
        .init(
            id: "geist",
            name: "Geist & Geist Mono",
            blurb: "Type families behind the Skoga UI body and monospace.",
            license: "OFL",
            licenseUrl: "https://github.com/vercel/geist-font/blob/main/LICENSE.TXT"
        ),
        .init(
            id: "newsreader",
            name: "Newsreader",
            blurb: "Serif used for the parchment headlines.",
            license: "OFL",
            licenseUrl: "https://github.com/productiontype/Newsreader/blob/master/OFL.txt"
        ),
    ]
}

private struct AcknowledgementRow: View {
    @Environment(\.palette) private var p
    let item: Acknowledgement
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                    Image(skoga: .doc).skogaIconSize(13).foregroundStyle(p.ink2)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(SkogaFont.bodyMedium(13))
                            .foregroundStyle(p.ink)
                        Text(item.license)
                            .font(SkogaFont.monoTiny(9.5))
                            .tracking(0.8)
                            .foregroundStyle(p.inkMute)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                                    .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                            )
                    }
                    Text(item.blurb)
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(skoga: .chevron).skogaIconSize(11)
                    .foregroundStyle(p.inkFaint)
                    .padding(.top, 8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(hovering ? p.paper3 : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Open \(item.name) license")
    }
}
