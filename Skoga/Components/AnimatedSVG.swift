import SwiftUI
import WebKit

/// Renders an SVG that uses SMIL animation (`<animate>` /
/// `<animateTransform>`). SwiftUI's `Image` rasterizes SVGs as static
/// vectors, so we host the markup inside a transparent WKWebView, which
/// is the easiest way to get SMIL playback on macOS. The SVG bytes are
/// read from a Data Set in the asset catalog so adding a new animation
/// is just dropping a `.svg` into `Assets.xcassets/<name>.dataset/`.
///
/// Reduce-motion handling: when the in-app preference
/// (`AppearancePrefs.reduceMotion`) or the system accessibility setting
/// is on, the loader strips `<animate>` / `<animateTransform>` elements
/// before handing the markup to WebKit so the asset renders as a single
/// pose. A SwiftUI `@Environment(\.accessibilityReduceMotion)` makes the
/// view re-render when the system pref flips, which re-runs `load(into:)`
/// via `updateNSView`.
struct AnimatedSVG: View {
    /// Asset-catalog data-set name (e.g. `"KongleCoffee"`).
    let assetName: String

    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @AppStorage(AppearancePrefs.reduceMotion) private var userReduce: Bool = AppearancePrefs.reduceMotionDefault

    var body: some View {
        SVGWebView(assetName: assetName, reduceMotion: systemReduce || userReduce)
    }
}

private struct SVGWebView: NSViewRepresentable {
    let assetName: String
    let reduceMotion: Bool

    /// Tracks the inputs that were last actually rendered into the
    /// WKWebView so `updateNSView` can early-out on unrelated SwiftUI
    /// invalidations (parent re-renders, palette changes, roster
    /// ticks). Without this, every body re-evaluation reloads HTML and
    /// resets SMIL playback — the empty-roster Kongle visibly jumps on
    /// every poll. Storing on a class lets us mutate from the
    /// (non-mutating) representable struct without an `inout`.
    final class Coordinator {
        var lastAsset: String?
        var lastReduceMotion: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastAsset != assetName
                || context.coordinator.lastReduceMotion != reduceMotion
        else { return }
        load(into: view, coordinator: context.coordinator)
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        guard let data = NSDataAsset(name: assetName)?.data,
              var svg = String(data: data, encoding: .utf8)
        else { return }
        if reduceMotion {
            svg = stripSMIL(svg)
        }
        // Strip the host page chrome down to nothing so the SVG fills the
        // bounds and the SwiftUI parent controls the size.
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: transparent;
                       width: 100%; height: 100%; overflow: hidden; }
          svg { display: block; width: 100%; height: 100%; }
        </style></head>
        <body>\(svg)</body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
        coordinator.lastAsset = assetName
        coordinator.lastReduceMotion = reduceMotion
    }

    /// Drops SMIL animation elements so the SVG renders as a static
    /// snapshot. Kongle assets use only `<animate>` and `<animateTransform>`
    /// (no `<animateMotion>` / CSS keyframes), so a regex-level strip is
    /// safe — adding a different animation primitive later would mean
    /// extending this list. Case-insensitive `<tag …/>` and `<tag …>…</tag>`
    /// both get matched; either form is valid SVG.
    private func stripSMIL(_ svg: String) -> String {
        let tags = ["animateTransform", "animate"]
        var output = svg
        for tag in tags {
            // Self-closing form: <animate … />
            let selfClosing = "(?i)<\(tag)\\b[^>]*/>"
            // Paired form: <animate …> … </animate>
            let paired = "(?i)<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>"
            for pattern in [selfClosing, paired] {
                output = output.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
        }
        return output
    }
}
