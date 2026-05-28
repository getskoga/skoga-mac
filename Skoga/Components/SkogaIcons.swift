import SwiftUI

/// Maps the lucide-shaped SVG icons from `components.jsx` onto SF Symbols.
/// SF Symbols don't all match shape-for-shape; we lean on the closest semantic.
/// Per-symbol weights/scales tuned to feel like the 1.5px strokes in the design.
enum SkogaIcon: String {
    case roster, dispatch, review, telemetry
    case settings, back, chevron, close, plus, pause, stop
    case branch, bolt, bug, shield, wrench, beaker, doc, github
    case check, alert, cmd, search, watch, spark, clock, loop, push

    /// Returns the SF Symbol name. Some are filled (we prefer outlined to match the design).
    var symbol: String {
        switch self {
        case .roster:    "list.bullet.indent"
        case .dispatch:  "arrow.right"
        case .review:    "arrow.triangle.branch"
        case .telemetry: "chart.line.uptrend.xyaxis"
        case .settings:  "gearshape"
        case .back:      "chevron.left"
        case .chevron:   "chevron.right"
        case .close:     "xmark"
        case .plus:      "plus"
        case .pause:     "pause.fill"
        case .stop:      "stop.fill"
        case .branch:    "arrow.triangle.branch"
        case .bolt:      "bolt"
        case .bug:       "ladybug"
        case .shield:    "shield"
        case .wrench:    "wrench.adjustable"
        case .beaker:    "testtube.2"
        case .doc:       "doc.text"
        case .github:    "chevron.left.forwardslash.chevron.right"
        case .check:     "checkmark"
        case .alert:     "exclamationmark.triangle"
        case .cmd:       "command"
        case .search:    "magnifyingglass"
        case .watch:     "bell"
        case .spark:     "sparkles"
        case .clock:     "clock"
        case .loop:      "arrow.triangle.2.circlepath"
        case .push:      "arrow.up.circle"
        }
    }
}

extension Image {
    init(skoga: SkogaIcon) {
        self.init(systemName: skoga.symbol)
    }
}

extension View {
    /// Tiny convenience for icon-sized SF Symbols. Matches `Icon size={…}` in JSX.
    func skogaIconSize(_ size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .regular))
            .frame(width: size + 2, height: size + 2)
    }
}

/// Role → glyph (1:1 with ROLE_ICON in components.jsx)
func iconForRole(_ role: String) -> SkogaIcon {
    switch role {
    case "backend / svc":      .branch
    case "frontend / web":     .bolt
    case "frontend / ui":      .bolt
    case "frontend / a11y":    .bolt
    case "qa / e2e":           .beaker
    case "qa / load":          .beaker
    case "devops / ci":        .wrench
    case "refactor":           .loop
    case "docs":               .doc
    case "data / migrate":     .branch
    case "data / etl":         .branch
    case "debug":              .bug
    case "security":           .shield
    case "api / contracts":    .branch
    case "perf":               .spark
    case "infra":              .wrench
    case "search":             .search
    case "backend / api":      .branch
    case "release":            .check
    default:                   .branch
    }
}
