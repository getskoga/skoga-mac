import SwiftUI
import WebKit

/// Renders an SVG that uses SMIL animation (`<animate>` /
/// `<animateTransform>`). SwiftUI's `Image` rasterizes SVGs as static
/// vectors, so we host the markup inside a transparent WKWebView, which
/// is the easiest way to get SMIL playback on macOS. The SVG bytes are
/// read from a Data Set in the asset catalog so adding a new animation
/// is just dropping a `.svg` into `Assets.xcassets/<name>.dataset/`.
struct AnimatedSVG: NSViewRepresentable {
    /// Asset-catalog data-set name (e.g. `"KongleCoffee"`).
    let assetName: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        load(into: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        load(into: view)
    }

    private func load(into view: WKWebView) {
        guard let data = NSDataAsset(name: assetName)?.data,
              let svg = String(data: data, encoding: .utf8)
        else { return }
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
    }
}
