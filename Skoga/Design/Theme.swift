import SwiftUI

/// Parchment-and-ledger palette. Tokens mirror styles.css 1:1.
/// Use `Theme.current.<token>` inside views; values respond to `.environment(\.colorScheme)`.
enum Theme {
    struct Palette {
        let paper: Color
        let paper2: Color
        let paper3: Color
        let paper4: Color
        let rule: Color
        let ruleHard: Color
        let ink: Color
        let ink2: Color
        let inkMute: Color
        let inkFaint: Color

        let forest: Color
        let forestDeep: Color
        let forestSoft: Color
        let ember: Color
        let emberSoft: Color
        let amber: Color
        let amberSoft: Color
        let dusk: Color
        let duskSoft: Color
        let moss: Color

        let cardShadow: Color
        let modalScrim: Color
    }

    static let light = Palette(
        paper:      .oklch(0.955, 0.018, 80),
        paper2:     .oklch(0.928, 0.026, 78),
        paper3:     .oklch(0.895, 0.030, 75),
        paper4:     .oklch(0.860, 0.035, 72),
        rule:       .oklch(0.78,  0.022, 70, opacity: 0.55),
        ruleHard:   .oklch(0.62,  0.025, 70, opacity: 0.70),
        ink:        .oklch(0.22,  0.012, 60),
        ink2:       .oklch(0.36,  0.014, 60),
        inkMute:    .oklch(0.50,  0.014, 60),
        inkFaint:   .oklch(0.62,  0.012, 60),

        forest:     .oklch(0.46, 0.085, 145),
        forestDeep: .oklch(0.34, 0.075, 145),
        forestSoft: .oklch(0.86, 0.040, 145),
        ember:      .oklch(0.58, 0.135, 38),
        emberSoft:  .oklch(0.88, 0.060, 50),
        amber:      .oklch(0.72, 0.110, 75),
        amberSoft:  .oklch(0.91, 0.060, 80),
        dusk:       .oklch(0.52, 0.075, 245),
        duskSoft:   .oklch(0.87, 0.040, 245),
        moss:       .oklch(0.58, 0.050, 130),

        cardShadow: .oklch(0.20, 0.01, 60, opacity: 0.06),
        modalScrim: .oklch(0.18, 0.012, 60, opacity: 0.35)
    )

    static let dark = Palette(
        paper:      .oklch(0.205, 0.012, 70),
        paper2:     .oklch(0.235, 0.014, 72),
        paper3:     .oklch(0.268, 0.016, 72),
        paper4:     .oklch(0.310, 0.018, 72),
        rule:       .oklch(0.42,  0.020, 72, opacity: 0.7),
        ruleHard:   .oklch(0.55,  0.025, 72, opacity: 0.8),
        ink:        .oklch(0.94,  0.018, 80),
        ink2:       .oklch(0.82,  0.018, 80),
        inkMute:    .oklch(0.65,  0.018, 80),
        inkFaint:   .oklch(0.50,  0.014, 70),

        forest:     .oklch(0.46, 0.085, 145),
        forestDeep: .oklch(0.34, 0.075, 145),
        forestSoft: .oklch(0.36, 0.060, 145),
        ember:      .oklch(0.58, 0.135, 38),
        emberSoft:  .oklch(0.40, 0.075, 38),
        amber:      .oklch(0.72, 0.110, 75),
        amberSoft:  .oklch(0.42, 0.080, 75),
        dusk:       .oklch(0.52, 0.075, 245),
        duskSoft:   .oklch(0.36, 0.060, 245),
        moss:       .oklch(0.58, 0.050, 130),

        cardShadow: .oklch(0.0, 0.0, 0, opacity: 0.25),
        modalScrim: .oklch(0.0, 0.0, 0, opacity: 0.55)
    )

    static func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Theme.Palette = Theme.light
}

extension EnvironmentValues {
    var palette: Theme.Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Resolves a palette from the current `ColorScheme` and injects it via `\.palette`.
    func withPalette() -> some View {
        modifier(PaletteResolver())
    }
}

private struct PaletteResolver: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.palette, Theme.palette(for: scheme))
    }
}
