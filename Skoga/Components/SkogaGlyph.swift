import SwiftUI

/// The Skoga "place-mark" glyph — pair of overlapping pines.
/// Mirrors the SVG path in components.jsx exactly.
struct SkogaGlyph: View {
    var size: CGFloat = 22
    var color: Color

    var body: some View {
        Canvas { ctx, _ in
            let scale = size / 24.0
            var trunk = Path()
            // Tree silhouette
            var tree = Path()
            tree.move(to:    CGPoint(x: 12, y: 2.5))
            tree.addLine(to: CGPoint(x: 18, y: 9.5))
            tree.addLine(to: CGPoint(x: 15.5, y: 9.5))
            tree.addLine(to: CGPoint(x: 20, y: 15))
            tree.addLine(to: CGPoint(x: 17, y: 15))
            tree.addLine(to: CGPoint(x: 21, y: 20))
            tree.addLine(to: CGPoint(x: 3,  y: 20))
            tree.addLine(to: CGPoint(x: 7,  y: 15))
            tree.addLine(to: CGPoint(x: 4,  y: 15))
            tree.addLine(to: CGPoint(x: 8.5, y: 9.5))
            tree.addLine(to: CGPoint(x: 6,  y: 9.5))
            tree.closeSubpath()

            // Trunk
            trunk.move(to: CGPoint(x: 12, y: 20))
            trunk.addLine(to: CGPoint(x: 12, y: 22.5))

            let scaled = CGAffineTransform(scaleX: scale, y: scale)
            ctx.fill(tree.applying(scaled), with: .color(color))
            ctx.stroke(
                trunk.applying(scaled),
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }
}
