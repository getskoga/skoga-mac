import SwiftUI

/// 30-tick activity sparkline. Inputs are raw per-bucket values (tokens/min
/// on the live path, a pre-normalized seed wave in mock) — the view scales
/// internally against the max of the series so the bar heights stay
/// sensible whether the guild is emitting 3k or 3M tok/min. Normalized
/// values over 0.85 are "hot" (ember), 0.65–0.85 are "warm" (amber), the
/// rest are forest. Mirrors `ActivityBars` in components.jsx.
struct ActivityBars: View {
    @Environment(\.palette) private var p
    let data: [Double]
    var height: CGFloat = 38

    var body: some View {
        GeometryReader { geo in
            let barWidth: CGFloat = 4
            let gap: CGFloat = 2
            let count = CGFloat(data.count)
            let totalGap = gap * max(0, count - 1)
            let availableWidth = geo.size.width
            let scale = max(0, min(1, (availableWidth - totalGap) / (barWidth * count)))
            // An idle guild has every bucket at 0; falling back to 1 here
            // keeps the divisor non-zero so the bars render as the 8px
            // floor baseline rather than NaN-clipping out of view.
            let peak = max(data.max() ?? 0, .leastNormalMagnitude)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, v in
                    let n = max(0, min(1, v / peak))
                    let h = max(8, CGFloat(n) * height)
                    bar(normalized: n)
                        .frame(width: barWidth * scale, height: h)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: height)
    }

    @ViewBuilder private func bar(normalized n: Double) -> some View {
        let (fill, opacity): (Color, Double) =
            n > 0.85 ? (p.ember,  0.85) :
            n > 0.65 ? (p.amber,  0.75) :
                       (p.forest, 0.40)

        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 1, bottomLeading: 0, bottomTrailing: 0, topTrailing: 1),
            style: .continuous
        )
        .fill(fill.opacity(opacity))
    }
}
