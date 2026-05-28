import SwiftUI
import Foundation

/// First-run wizard state. Owns the six-step flow's data (default model,
/// github status, sandbox config, workspace) and persists it to
/// UserDefaults so re-running from Settings · About restores the wizard
/// with previous values pre-filled. The `completed` flag is the
/// app-level gate read by `SkogaApp` to decide whether to mount the
/// onboarding overlay.
@MainActor
@Observable
final class OnboardingState {

    /// Step index into `OnboardingStep.allCases`. Mutated by Back / Next /
    /// Skip-for-now and bounded by the underlying `next()` / `back()`
    /// helpers — direct writes are fine but should stay in range.
    var step: Int = 0

    /// Wizard-level data. Treat as a single value; mutations always
    /// flow through `update(_:)` so persistence stays in sync without
    /// individual property observers.
    private(set) var data: OnboardingData

    /// Whether the user has finished (or explicitly skipped) the wizard.
    /// Mirrored to `UserDefaults.standard` under `Self.completedKey` so
    /// a freshly-launched app skips straight to the cockpit. Settings ·
    /// About flips this back to `false` to re-run the wizard.
    var completed: Bool {
        didSet { UserDefaults.standard.set(completed, forKey: Self.completedKey) }
    }

    static let completedKey = "skoga.onboarding.completed"
    private static let dataKey = "skoga.onboarding.data"

    init() {
        self.completed = UserDefaults.standard.bool(forKey: Self.completedKey)
        if let raw = UserDefaults.standard.data(forKey: Self.dataKey),
           let decoded = try? JSONDecoder().decode(OnboardingData.self, from: raw) {
            self.data = decoded
        } else {
            self.data = OnboardingData()
        }
    }

    /// Patch-style update so views can write `update { $0.defaultModel = "…" }`
    /// without each step inventing its own setter. The persisted blob is
    /// rewritten on every change — the payload is small enough (a few
    /// hundred bytes) that the throughput cost is invisible.
    func update(_ patch: (inout OnboardingData) -> Void) {
        patch(&data)
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.dataKey)
        }
    }

    func next() {
        step = min(step + 1, OnboardingStep.allCases.count - 1)
    }

    func back() {
        step = max(step - 1, 0)
    }

    /// Reset the step pointer to the first card while preserving the
    /// stored values. Used by `restart()` so re-running the wizard
    /// from Settings drops the user on the welcome card with their
    /// previous picks intact.
    func restart() {
        step = 0
        completed = false
    }

    /// Hard reset — wipes the persisted data blob and the completed
    /// flag so the next launch behaves like a brand-new install.
    /// Backs Settings → Privacy → "Reset first-run state", which is
    /// the developer / QA escape hatch (the About panel's "Re-run
    /// onboarding" preserves data on purpose).
    func resetFirstRun() {
        data = OnboardingData()
        UserDefaults.standard.removeObject(forKey: Self.dataKey)
        step = 0
        completed = false
    }

    /// Mark the wizard finished. The persisted `data` blob is left
    /// intact so a later restart can pre-fill the same values.
    func finish() {
        completed = true
    }
}

/// Per-step data captured by the wizard. Codable so it can round-trip
/// through UserDefaults; Equatable so SwiftUI's `onChange(of:)` can
/// observe sub-field mutations.
struct OnboardingData: Codable, Equatable {
    var defaultModel: String = "claude-opus-4.7"
    var github: GitHubInfo? = nil
    var sandbox: SandboxInfo = SandboxInfo()
    var workspace: String = "~/code"

    struct GitHubInfo: Codable, Equatable {
        var account: String = ""
        var orgs: Int = 0
        var repos: Int = 0
    }

    struct SandboxInfo: Codable, Equatable {
        var on: Bool = true
        var pat: String = ""
        var vault: String? = nil
        /// Map of carveout id → enabled. Defaults are applied in
        /// `StepSandbox` so a fresh install gets the iOS/macOS build
        /// chain pre-toggled even without anything in UserDefaults yet.
        var carveouts: [String: Bool] = [:]
    }
}

/// Six-step ordering. The string raw values match the design's progress
/// pips (Welcome · Model · GitHub · Sandbox · Forest · Ready).
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case model
    case github
    case sandbox
    case forest
    case ready

    var label: String {
        switch self {
        case .welcome:  "Welcome"
        case .model:    "Model"
        case .github:   "GitHub"
        case .sandbox:  "Sandbox"
        case .forest:   "Forest"
        case .ready:    "Ready"
        }
    }
}
