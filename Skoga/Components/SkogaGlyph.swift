import SwiftUI

/// The Skoga "place-mark" — a pair of overlapping pines. The back tree paints in
/// `--forest-soft` (sage), the front tree in `--forest` (deep), establishing a
/// shallow depth without using opacity or strokes.
struct SkogaGlyph: View {
    @Environment(\.palette) private var p

    var size: CGFloat = 22
    /// Front-tree (deep) tint. Defaults to the active palette's forest.
    var color: Color? = nil
    /// Back-tree (sage) tint. Defaults to the active palette's forestSoft, darkened a touch.
    var backColor: Color? = nil

    var body: some View {
        Canvas { ctx, _ in
            let scale = size / 24.0
            let xf = CGAffineTransform(scaleX: scale, y: scale)

            // Back tree — slightly smaller, shifted up-left
            let back = treePath(centerX: 8.6, top: 4.8, baseY: 19.2, halfWidth: 4.6)
            let backTrunk = trunkPath(x: 8.6, top: 19.2, bottom: 21.0)
            ctx.fill(back.applying(xf), with: .color(backColor ?? p.moss))
            ctx.stroke(
                backTrunk.applying(xf),
                with: .color(backColor ?? p.moss),
                style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round)
            )

            // Front tree — taller, anchored to the right; overlaps the back one
            let front = treePath(centerX: 14.4, top: 2.4, baseY: 20.0, halfWidth: 6.2)
            let frontTrunk = trunkPath(x: 14.4, top: 20.0, bottom: 22.4)
            ctx.fill(front.applying(xf), with: .color(color ?? p.forest))
            ctx.stroke(
                frontTrunk.applying(xf),
                with: .color(color ?? p.forest),
                style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }

    /// A three-tier stylized conifer silhouette, anchored at (centerX, top..baseY).
    private func treePath(centerX cx: CGFloat, top: CGFloat, baseY: CGFloat, halfWidth hw: CGFloat) -> Path {
        // Vertical waypoints across the three tiers
        let h = baseY - top
        let row1 = top + h * 0.32     // top tier base
        let row1In = top + h * 0.30   // overhang inset
        let row2 = top + h * 0.62     // mid tier base
        let row2In = top + h * 0.60
        let inset: CGFloat = hw * 0.45    // how far the upper tiers shoulder inward
        let inset2: CGFloat = hw * 0.20   // mid tier inward shoulder

        var p = Path()
        p.move(to:    CGPoint(x: cx,                y: top))             // peak
        p.addLine(to: CGPoint(x: cx + hw * 0.55,    y: row1))
        p.addLine(to: CGPoint(x: cx + hw * 0.55 - inset, y: row1In))
        p.addLine(to: CGPoint(x: cx + hw * 0.82,    y: row2))
        p.addLine(to: CGPoint(x: cx + hw * 0.82 - inset2, y: row2In))
        p.addLine(to: CGPoint(x: cx + hw,           y: baseY))
        p.addLine(to: CGPoint(x: cx - hw,           y: baseY))
        p.addLine(to: CGPoint(x: cx - hw * 0.82 + inset2, y: row2In))
        p.addLine(to: CGPoint(x: cx - hw * 0.82,    y: row2))
        p.addLine(to: CGPoint(x: cx - hw * 0.55 + inset, y: row1In))
        p.addLine(to: CGPoint(x: cx - hw * 0.55,    y: row1))
        p.closeSubpath()
        return p
    }

    private func trunkPath(x: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: top))
        p.addLine(to: CGPoint(x: x, y: bottom))
        return p
    }
}
