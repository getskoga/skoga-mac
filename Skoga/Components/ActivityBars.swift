import SwiftUI

/// 30-tick activity sparkline. Bars over 0.85 are "hot" (ember), 0.65–0.85 are
/// "warm" (amber), the rest are forest. Mirrors `ActivityBars` in components.jsx.
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

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, v in
                    let h = max(8, CGFloat(v) * height)
                    bar(v: v)
                        .frame(width: barWidth * scale, height: h)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: height)
    }

    @ViewBuilder private func bar(v: Double) -> some View {
        let (fill, opacity): (Color, Double) =
            v > 0.85 ? (p.ember,  0.85) :
            v > 0.65 ? (p.amber,  0.75) :
                       (p.forest, 0.40)

        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 1, bottomLeading: 0, bottomTrailing: 0, topTrailing: 1),
            style: .continuous
        )
        .fill(fill.opacity(opacity))
    }
}
