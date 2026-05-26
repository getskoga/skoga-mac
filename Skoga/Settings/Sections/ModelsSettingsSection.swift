import SwiftUI
import AppKit

/// Settings → Models & keys. Renders one card per provider whose adapter
/// Skoga supports (`RPCCredentialProvider.allCases`), each with:
///   - status chip (Connected · used Xm ago / Not configured)
///   - API key input (masked, show/hide toggle, Save + Clear)
///   - Test connection button with an inline pass/fail result
///   - Default model picker for that provider's adapter
///
/// Mounted by `SettingsShell` when the Models & keys row is selected.
/// The shell provides the scroll container, padding, and max-width
/// frame, so this view just stacks its header + per-provider cards.
///
/// Priority order for the top-level rendered state mirrors the GitHub
/// section: daemon-unsupported and transport errors win over the
/// per-provider list because acting on a daemon that can't persist the
/// key would silently no-op.
struct ModelsSettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(DaemonClientHolder.self) private var daemon

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if daemon.credentialsDaemonUnsupported {
                daemonUnsupportedCard
            } else if daemon.credentialEntries.isEmpty, let err = daemon.credentialsError {
                errorCard(err)
            } else if daemon.credentialEntries.isEmpty {
                loadingCard
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(daemon.credentialEntries) { entry in
                        ProviderCard(entry: entry)
                            .id(entry.provider)
                    }
                }
            }
        }
        .task { await daemon.refreshCredentials() }
    }

    // MARK: – Section header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.modelsKeys.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.modelsKeys.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text("API keys for the model providers Skoga's adapters consume. Stored in your macOS login Keychain and handed to each agent at launch — never written to disk by the daemon.")
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    // MARK: – Status-card variants

    private var daemonUnsupportedCard: some View {
        sectionCard {
            statusRow(
                dot: p.amber,
                headline: "Skoga daemon is too old",
                detail: "This skogad build doesn't speak `credentials.*` yet. Upgrade the daemon to manage API keys from Settings.",
                cta: .init(label: "Re-check", icon: .loop) {
                    Task { await daemon.refreshCredentials() }
                },
                secondary: nil
            )
        }
    }

    private func errorCard(_ message: String) -> some View {
        sectionCard {
            statusRow(
                dot: p.ember,
                headline: "Couldn't reach the daemon",
                detail: message,
                cta: .init(label: "Retry", icon: .loop) {
                    Task { await daemon.refreshCredentials() }
                },
                secondary: nil
            )
        }
    }

    private var loadingCard: some View {
        sectionCard {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading Keychain…")
                    .font(SkogaFont.mono(11.5))
                    .foregroundStyle(p.inkMute)
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private struct ActionSpec {
        let label: String
        let icon: SkogaIcon
        let action: () -> Void
    }

    private func statusRow(
        dot: Color,
        headline: String,
        detail: String,
        cta: ActionSpec,
        secondary: ActionSpec?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(dot.opacity(0.22), lineWidth: 3))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(SkogaFont.bodyMedium(13))
                    .foregroundStyle(p.ink)
                Text(detail)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    primaryButton(label: cta.label, icon: cta.icon, action: cta.action)
                    if let secondary {
                        secondaryButton(label: secondary.label, icon: secondary.icon, action: secondary.action)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private func primaryButton(label: String, icon: SkogaIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(skoga: icon).skogaIconSize(12)
                Text(label).font(SkogaFont.bodyMedium(12))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(label: String, icon: SkogaIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(skoga: icon).skogaIconSize(12)
                Text(label).font(SkogaFont.bodyMedium(12))
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
    }
}

// MARK: – Per-provider card

/// One provider's row. Owns its own draft/show/saving/testing state so
/// the parent doesn't have to thread per-row local state through the
/// coordinator — the parent only persists the final key (via
/// `coordinator.setCredential`) and reads the cached entry for the
/// chip from the daemon slice.
private struct ProviderCard: View {
    @Environment(\.palette) private var p
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(DaemonClientHolder.self) private var daemon
    let entry: RPCCredentialEntry

    /// In-progress text the user is typing. Empty when the row mounts
    /// with a configured key (we never read the key back — the daemon
    /// keeps it in Keychain). Cleared after a successful save so the
    /// row falls back to the masked "•••••" placeholder.
    @State private var draft: String = ""
    @State private var showing: Bool = false
    @State private var saving: Bool = false
    @State private var testing: Bool = false

    private var provider: RPCCredentialProvider { entry.provider }
    private var hasKey: Bool { entry.has_key }
    private var canSubmit: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader
            statusChipRow
            keyInputRow
            actionsRow
            if let result = daemon.credentialTestResults[provider] {
                testResultRow(result)
            }
            Hairline()
            DefaultModelPicker(provider: provider)
        }
        .padding(18)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private var cardHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(p.paper3)
                Image(skoga: .spark).skogaIconSize(13).foregroundStyle(p.ink2)
            }
            .frame(width: 28, height: 28)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.rule, lineWidth: Tokens.Hairline.width))

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(SkogaFont.serifHeading(16))
                    .foregroundStyle(p.ink)
                Text("Used by `\(provider.adapter)` adapter.")
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkFaint)
            }
            Spacer()
        }
    }

    private var statusChipRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(hasKey ? p.forest : p.amber)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke((hasKey ? p.forest : p.amber).opacity(0.22), lineWidth: 3))
            if hasKey {
                Text("Connected")
                    .font(SkogaFont.bodyMedium(12.5))
                    .foregroundStyle(p.ink2)
                if let label = lastUsedLabel(entry.last_used) {
                    Text("·")
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkFaint)
                    Text(label)
                        .font(SkogaFont.monoSmall(11))
                        .foregroundStyle(p.inkMute)
                }
            } else {
                Text("Not configured")
                    .font(SkogaFont.bodyMedium(12.5))
                    .foregroundStyle(p.ink2)
                Text("·")
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkFaint)
                Text("Skoga can't dispatch \(provider.adapter) sessions until you add a key.")
                    .font(SkogaFont.body(11.5))
                    .foregroundStyle(p.inkMute)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var keyInputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API KEY")
                .font(SkogaFont.mono(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)

            HStack(spacing: 8) {
                Group {
                    if showing {
                        TextField(placeholderText, text: $draft)
                    } else {
                        // SecureField masks the input as the user types
                        // — Mac password-style. Toggling `showing` flips
                        // to a plain TextField so the user can sanity-
                        // check the value before saving.
                        SecureField(placeholderText, text: $draft)
                    }
                }
                .textFieldStyle(.plain)
                .font(SkogaFont.mono(12))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(p.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .disabled(saving)
                .onSubmit { Task { await save() } }

                Button {
                    showing.toggle()
                } label: {
                    Image(systemName: showing ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(p.ink2)
                        .frame(width: 30, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                .fill(p.paper)
                                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                        )
                }
                .buttonStyle(.plain)
                .help(showing ? "Hide key" : "Show key")
            }
        }
    }

    private var placeholderText: String {
        // Provider-specific placeholders give a strong "is this the
        // right shape?" affordance without dictating a format
        // (Anthropic keys are `sk-ant-…`, OpenAI keys are `sk-…`).
        switch provider {
        case .anthropic: hasKey ? "Enter a new key to rotate" : "sk-ant-…"
        case .openai:    hasKey ? "Enter a new key to rotate" : "sk-…"
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if saving {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(skoga: .check).skogaIconSize(11)
                    }
                    Text(hasKey ? "Rotate" : "Save").font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.chip).fill(p.forest))
                .opacity(canSubmit ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            Button {
                Task { await test() }
            } label: {
                HStack(spacing: 6) {
                    if testing {
                        ProgressView().controlSize(.small).tint(p.ink2)
                    } else {
                        Image(skoga: .bolt).skogaIconSize(11)
                    }
                    Text(testing ? "Testing…" : "Test connection").font(SkogaFont.bodyMedium(12))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(p.ink2)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(p.paper)
                        .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                )
                .opacity(hasKey && !testing ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            // The probe needs a configured key. Don't let the user click
            // it on an empty row — the daemon would just return ok:false
            // with "no key configured", which is more confusing than the
            // disabled affordance.
            .disabled(!hasKey || testing)

            if hasKey {
                Button {
                    Task { await clear() }
                } label: {
                    HStack(spacing: 6) {
                        Image(skoga: .close).skogaIconSize(11)
                        Text("Clear").font(SkogaFont.bodyMedium(12))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .foregroundStyle(p.ember)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .fill(p.paper)
                            .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                    )
                }
                .buttonStyle(.plain)
                .disabled(saving || testing)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func testResultRow(_ result: RPCCredentialsTestResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(result.ok ? p.forest : p.ember)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke((result.ok ? p.forest : p.ember).opacity(0.22), lineWidth: 3))
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(result.ok ? "Probe succeeded" : "Probe failed")
                        .font(SkogaFont.bodyMedium(12))
                        .foregroundStyle(p.ink)
                    if let ms = result.latency_ms {
                        Text("\(ms) ms")
                            .font(SkogaFont.monoSmall(10.5))
                            .foregroundStyle(p.inkFaint)
                    }
                    Spacer()
                }
                Text(result.message)
                    .font(SkogaFont.body(12))
                    .foregroundStyle(p.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(p.paper)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .stroke((result.ok ? p.forest : p.ember).opacity(0.45), lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
    }

    // MARK: – Actions

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        defer { saving = false }
        let ok = await coordinator.setCredential(provider: provider, key: trimmed)
        if ok {
            // Clear the draft on success so the row falls back to the
            // masked placeholder — leaving a real key visible in the
            // field is a footgun (visible on screen-share, visible to a
            // bystander). If the user wants to rotate again they can
            // paste the new key fresh.
            draft = ""
            showing = false
        }
    }

    private func clear() async {
        _ = await coordinator.deleteCredential(provider: provider)
        draft = ""
        showing = false
    }

    private func test() async {
        testing = true
        defer { testing = false }
        _ = await coordinator.testCredential(provider: provider)
    }

    /// Render the entry's `last_used` ISO-8601 timestamp as a friendly
    /// "Xm ago" / "Xh ago" relative label. Returns nil for a key that
    /// has never been read (the daemon-side timestamp is set on agent
    /// launch and on `credentials.test`, so a freshly-saved key with no
    /// session yet stays in the "no read" state).
    private func lastUsedLabel(_ iso: String?) -> String? {
        guard let iso, let date = Self.iso.date(from: iso) else { return nil }
        let delta = Int(Date().timeIntervalSince(date))
        if delta < 60 { return "used just now" }
        if delta < 3600 { return "used \(delta / 60)m ago" }
        if delta < 86_400 { return "used \(delta / 3600)h ago" }
        return "used \(delta / 86_400)d ago"
    }

    // ISO-8601 with fractional seconds is what the daemon emits; using
    // a shared formatter avoids per-row reconstruction on every paint.
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: – Default model picker

/// Per-provider default-model picker. Persisted in `@AppStorage` under
/// `skoga.defaultModel.<adapter>` so DispatchView can read the same key
/// at mount time. The picker only enumerates models whose adapter
/// matches `provider.adapter` — there's no reason to surface Codex
/// models in the Anthropic card or vice versa.
private struct DefaultModelPicker: View {
    @Environment(\.palette) private var p
    let provider: RPCCredentialProvider

    @AppStorage private var stored: String

    init(provider: RPCCredentialProvider) {
        self.provider = provider
        self._stored = AppStorage(
            wrappedValue: DefaultModelPreference.defaultValue(for: provider),
            DefaultModelPreference.storageKey(for: provider)
        )
    }

    private var choices: [DispatchView.ModelChoice] {
        DispatchView.modelChoices.filter { $0.adapter == provider.adapter }
    }

    private var currentLabel: String {
        choices.first(where: { $0.model == stored })?.label ?? stored
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEFAULT MODEL")
                .font(SkogaFont.mono(10))
                .tracking(1.0)
                .foregroundStyle(p.inkFaint)

            Menu {
                ForEach(choices, id: \.self) { choice in
                    Button(choice.label) { stored = choice.model }
                }
            } label: {
                HStack {
                    Text(currentLabel).font(SkogaFont.body(13))
                    Spacer()
                    Image(skoga: .chevron).skogaIconSize(10)
                        .rotationEffect(.degrees(90))
                }
                .foregroundStyle(p.ink)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(p.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.input)
                        .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.input))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Text("Pre-selected in the Dispatch form's model dropdown. You can still pick a different model per run.")
                .font(SkogaFont.body(11.5))
                .foregroundStyle(p.inkMute)
        }
    }
}

/// Single source of truth for the default-model AppStorage keys + their
/// defaults. Lives outside `DefaultModelPicker` so `DispatchView` can
/// reuse the same key/default when seeding its initial selection — if
/// the two diverged, the Dispatch form's initial pick wouldn't match
/// the Settings page's persisted choice on cold launch.
enum DefaultModelPreference {
    static func storageKey(for provider: RPCCredentialProvider) -> String {
        "skoga.defaultModel.\(provider.adapter)"
    }

    static func defaultValue(for provider: RPCCredentialProvider) -> String {
        switch provider {
        case .anthropic: "claude-opus-4-7"
        case .openai:    "gpt-5-codex"
        }
    }

    /// Resolve the persisted default for `adapter`, falling back to the
    /// hardcoded default when nothing is stored. Used by DispatchView at
    /// `@State` init time, where SwiftUI's `@AppStorage` isn't directly
    /// available.
    static func resolve(adapter: String) -> String {
        let key = "skoga.defaultModel.\(adapter)"
        let fallback: String = {
            switch adapter {
            case "claude": "claude-opus-4-7"
            case "codex":  "gpt-5-codex"
            default:       ""
            }
        }()
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }
}
