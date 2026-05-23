import SwiftUI

/// Type tokens. Maps to Geist / Geist Mono / Newsreader when bundled in `Skoga/App/Fonts/`;
/// otherwise falls back to the closest system family (SF Pro / SF Mono / New York).
enum SkogaFont {
    enum Family: String {
        case sans = "Geist"
        case mono = "Geist Mono"
        case serif = "Newsreader"
    }

    /// Builds a Font that prefers the design's family but falls back to system if unavailable.
    static func font(_ family: Family, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let nsFont = NSFont(name: family.rawValue, size: size)
        if nsFont != nil {
            return Font.custom(family.rawValue, size: size).weight(weight)
        }
        // Fallbacks tuned to the design's intent:
        switch family {
        case .sans:  return .system(size: size, weight: weight, design: .default)
        case .mono:  return .system(size: size, weight: weight, design: .monospaced)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        }
    }

    // ── Display ──────────────────────────────────────────────
    static func serifTitle(_ size: CGFloat = 26)    -> Font { font(.serif, size: size, weight: .medium) }
    static func serifHeading(_ size: CGFloat = 21)  -> Font { font(.serif, size: size, weight: .medium) }
    static func serifName(_ size: CGFloat = 16)     -> Font { font(.serif, size: size, weight: .medium) }
    static func serifValue(_ size: CGFloat = 26)    -> Font { font(.serif, size: size, weight: .regular) }

    // ── Body ──────────────────────────────────────────────
    static func body(_ size: CGFloat = 13.5)        -> Font { font(.sans, size: size, weight: .regular) }
    static func bodyMedium(_ size: CGFloat = 12)    -> Font { font(.sans, size: size, weight: .medium) }
    static func small(_ size: CGFloat = 11.5)       -> Font { font(.sans, size: size, weight: .regular) }
    static func smallMedium(_ size: CGFloat = 11.5) -> Font { font(.sans, size: size, weight: .medium) }

    // ── Mono / labels ────────────────────────────────────────
    static func mono(_ size: CGFloat = 11)          -> Font { font(.mono, size: size, weight: .regular) }
    static func monoSmall(_ size: CGFloat = 10.5)   -> Font { font(.mono, size: size, weight: .regular) }
    static func monoTiny(_ size: CGFloat = 9.5)     -> Font { font(.mono, size: size, weight: .regular) }
    static func monoLabel(_ size: CGFloat = 10)     -> Font { font(.mono, size: size, weight: .medium) }
}
