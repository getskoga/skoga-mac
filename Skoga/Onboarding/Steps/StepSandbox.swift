import SwiftUI
import AppKit

/// Step 4 — Sandbox. Master `sandbox-exec` toggle + three sub-blocks
/// (agent's GitHub PAT, secrets vault, carveouts). Mirrors the design's
/// "lock the runtime down" stance — sandbox stays on by default; the
/// stack of cards disables (grayed out, hit-testing off) when the user
/// flips it off.
struct StepSandbox: View {
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL
    @Environment(OnboardingState.self) private var state
    let onNext: () -> Void
    let onBack: () -> Void

    /// Apple-fine-grained-PAT creation page. Mirrors what `Settings ·
    /// GitHub` opens when the user runs `gh auth refresh` — keeping the
    /// destination consistent across surfaces.
    private static let patURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    /// Default carveouts list. Order matches the design — pre-enabled
    /// iOS/macOS build chain first, then the riskier system tools the
    /// user has to opt into.
    static let defaultCarveouts: [Carveout] = [
        .init(id: "xcodebuild",     bin: "xcodebuild",     desc: "Build Xcode projects · iOS & macOS targets", on: true),
        .init(id: "simctl",         bin: "xcrun simctl",   desc: "Control the iOS Simulator",                   on: true),
        .init(id: "sw_vers",        bin: "sw_vers",        desc: "Read macOS version info",                     on: true),
        .init(id: "osascript",      bin: "osascript",      desc: "Run AppleScript (system automation)",         on: false),
        .init(id: "softwareupdate", bin: "softwareupdate", desc: "Trigger OS-level updates",                    on: false),
        .init(id: "networksetup",   bin: "networksetup",   desc: "Read or modify network config",               on: false),
    ]

    private static let recommendedScopes: [String] = [
        "contents · read",
        "metadata · read",
        "issues · read",
        "pull requests · read",
        "actions · read",
    ]

    private static let writeScope = "contents · write"

    private static let vaults: [Vault] = [
        .init(id: "1password", label: "1Password CLI",   sub: "op vault, biometric unlock"),
        .init(id: "bitwarden", label: "Bitwarden",       sub: "bw cli, session token"),
        .init(id: "keychain",  label: "macOS Keychain",  sub: "security find-generic-password"),
        .init(id: "doppler",   label: "Doppler",         sub: "doppler secrets get"),
        .init(id: "none",      label: "Skip",            sub: "I'll provide secrets per-run"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHead(
                eyebrow: "Step 4 · Sandbox",
                title: "Lock the runtime down.",
                body: AnyView(StepLede("Each agent runs inside sandbox-exec with a deny-by-default policy — no network beyond what you allow, no filesystem access outside its worktree, no Keychain. You poke deliberate holes for the things real builds need."))
            )

            masterToggle

            VStack(alignment: .leading, spacing: 14) {
                patBlock
                vaultBlock
                carveoutBlock
            }
            .opacity(state.data.sandbox.on ? 1 : 0.45)
            .saturation(state.data.sandbox.on ? 1 : 0.6)
            .allowsHitTesting(state.data.sandbox.on)

            OnboardingActions(onBack: onBack) {
                OBPrimaryButton(label: "Continue", action: onNext)
            }
        }
        .onAppear { seedDefaultsIfNeeded() }
    }

    // MARK: – Master toggle

    private var masterToggle: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(state.data.sandbox.on ? p.forestSoft.opacity(0.6) : p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(state.data.sandbox.on ? Color.oklch(0.6, 0.06, 145, opacity: 0.4) : p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .frame(width: 40, height: 40)
                Image(skoga: .shield).skogaIconSize(20)
                    .foregroundStyle(state.data.sandbox.on ? p.forest : p.inkMute)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Sandbox every agent")
                        .font(SkogaFont.serifName(19).weight(.medium))
                        .foregroundStyle(p.ink)
                    Text("STRONGLY RECOMMENDED")
                        .font(SkogaFont.monoTiny(9.5).weight(.medium))
                        .tracking(0.76)
                        .foregroundStyle(Color.oklch(0.97, 0.02, 90))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.tiny).fill(p.forest))
                }
                Text(state.data.sandbox.on
                     ? "Agents can't reach the rest of your machine. Net, FS, and tool access are governed by the policy below."
                     : "Agents will run with your full user permissions. Skoga can't help you if a run goes sideways.")
                    .font(SkogaFont.body(12.5))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(12.5 * 0.5)
                    .frame(maxWidth: 580, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            OBSwitch(isOn: state.data.sandbox.on) {
                state.update { $0.sandbox.on.toggle() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .fill(state.data.sandbox.on ? p.forestSoft.opacity(0.5) : p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.modal)
                .stroke(state.data.sandbox.on ? Color.oklch(0.5, 0.08, 145, opacity: 0.55) : p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    // MARK: – PAT block

    private var patBlock: some View {
        sandboxCard {
            VStack(alignment: .leading, spacing: 12) {
                blockHead(
                    title: "Agent's GitHub PAT",
                    subtitle: "A fine-grained token the agent uses to read repos. Your OAuth (last step) handles PRs as you — this is separate, deliberately weaker.",
                    link: "Generate token →",
                    linkAction: { openURL(Self.patURL) }
                )

                TextField("github_pat_…", text: Binding(
                    get: { state.data.sandbox.pat },
                    set: { newValue in state.update { $0.sandbox.pat = newValue } }
                ))
                    .textFieldStyle(.plain)
                    .font(SkogaFont.mono(12))
                    .foregroundStyle(p.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(p.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .disabled(!state.data.sandbox.on)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SUGGESTED SCOPES · ALL READ-ONLY")
                        .font(SkogaFont.monoTiny(9.5))
                        .tracking(0.76)
                        .foregroundStyle(p.inkFaint)
                    HStack(spacing: 5) {
                        ForEach(Self.recommendedScopes, id: \.self) { scope in
                            scopeChip(scope, on: true)
                        }
                        scopeChip(Self.writeScope, on: false)
                    }
                }
            }
        }
    }

    private func scopeChip(_ text: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            if on {
                Image(skoga: .check).skogaIconSize(10)
            }
            Text(text)
                .font(SkogaFont.mono(11))
                .strikethrough(!on)
        }
        .foregroundStyle(on ? p.forest : p.inkMute.opacity(0.55))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(on ? p.forestSoft : p.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(on ? Color.oklch(0.6, 0.06, 145, opacity: 0.4) : p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    // MARK: – Vault block

    private var vaultBlock: some View {
        sandboxCard {
            VStack(alignment: .leading, spacing: 12) {
                blockHead(
                    title: "Secrets vault",
                    subtitle: "When an agent needs STRIPE_KEY or DATABASE_URL, Skoga injects from the vault at run time — secrets never sit in env files inside the worktree.",
                    link: nil,
                    linkAction: nil
                )

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 160), spacing: 8)
                ], alignment: .leading, spacing: 8) {
                    ForEach(Self.vaults) { vault in
                        vaultButton(vault)
                    }
                }
            }
        }
    }

    private func vaultButton(_ vault: Vault) -> some View {
        let selected = state.data.sandbox.vault == vault.id

        return Button(action: {
            state.update { $0.sandbox.vault = vault.id }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vault.label)
                    .font(SkogaFont.serifName(14).weight(.medium))
                    .foregroundStyle(p.ink)
                Text(vault.sub)
                    .font(SkogaFont.monoTiny(10))
                    .tracking(0.4)
                    .foregroundStyle(p.inkFaint)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .fill(selected ? p.paper3 : p.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.input)
                    .stroke(selected ? p.forest : p.rule, lineWidth: selected ? 1 : Tokens.Hairline.width)
            )
        }
        .buttonStyle(.plain)
        .disabled(!state.data.sandbox.on)
    }

    // MARK: – Carveouts block

    private var carveoutBlock: some View {
        sandboxCard {
            VStack(alignment: .leading, spacing: 12) {
                blockHead(
                    title: "Allowed carveouts",
                    subtitle: "Tools the sandbox can call out to. Add or remove anytime in Settings · Sandbox. We pre-enable the common iOS/macOS build chain.",
                    link: nil,
                    linkAction: nil
                )

                VStack(spacing: 4) {
                    ForEach(Self.defaultCarveouts) { carveout in
                        carveoutRow(carveout)
                    }
                }

                // The design's "Add a carveout" placeholder is omitted in
                // the wizard — per the issue, custom carveouts live in
                // Settings · Sandbox. A dead button on this surface would
                // misrepresent what onboarding can do. The settings-note
                // below already tells the user where to add more.

                HStack(alignment: .top, spacing: 7) {
                    Image(skoga: .settings).skogaIconSize(11)
                        .foregroundStyle(p.inkFaint)
                        .padding(.top, 2)
                    Text(LocalizedStringKey("You can add or remove carveouts later in **Settings · Sandbox**. Skoga also surfaces a prompt the first time an agent hits a blocked binary, so you can approve on demand."))
                        .font(SkogaFont.body(11.5))
                        .foregroundStyle(p.inkMute)
                        .lineSpacing(11.5 * 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(p.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(p.rule, style: StrokeStyle(lineWidth: Tokens.Hairline.width, dash: [3, 3]))
                )
                .padding(.top, 2)
            }
        }
    }

    private func carveoutRow(_ carveout: Carveout) -> some View {
        let on = state.data.sandbox.carveouts[carveout.id] ?? carveout.on

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(carveout.bin)
                    .font(SkogaFont.mono(12.5).weight(.medium))
                    .foregroundStyle(p.ink)
                Text(carveout.desc)
                    .font(SkogaFont.body(11.5))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(11.5 * 0.45)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            OBSwitch(isOn: on, disabled: !state.data.sandbox.on) {
                state.update { $0.sandbox.carveouts[carveout.id] = !on }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(on ? p.paper3 : p.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(on ? p.ruleHard : p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    // MARK: – Shared sub-card chrome

    @ViewBuilder
    private func sandboxCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(p.paper2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
    }

    @ViewBuilder
    private func blockHead(title: String, subtitle: String, link: String?, linkAction: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SkogaFont.serifName(16).weight(.medium))
                    .foregroundStyle(p.ink)
                Text(subtitle)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .lineSpacing(12 * 0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link, let linkAction {
                Spacer(minLength: 8)
                Button(action: linkAction) {
                    Text(link)
                        .font(SkogaFont.mono(11))
                        .foregroundStyle(p.forest)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: – Default carveout seeding

    private func seedDefaultsIfNeeded() {
        guard state.data.sandbox.carveouts.isEmpty else { return }
        state.update {
            $0.sandbox.carveouts = Dictionary(uniqueKeysWithValues: Self.defaultCarveouts.map { ($0.id, $0.on) })
        }
    }

    struct Carveout: Identifiable {
        let id: String
        let bin: String
        let desc: String
        let on: Bool
    }

    struct Vault: Identifiable {
        let id: String
        let label: String
        let sub: String
    }
}
