import SwiftUI

/// The instrument-cluster strip at the top of the roster. Four metric cells +
/// a sparkline. Each cell renders as label/value/sub, separated by hairline rules.
struct CockpitStrip: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    var body: some View {
        let counts = state.counts
        let spend = state.spend

        HStack(spacing: 0) {
            Instrument(
                label: "Active",
                value: "\(counts.running)",
                unit: "agents",
                sub: "\(counts.tokens.formattedWithSeparators()) tok · last 5m",
                dot: .running,
                attention: false
            )

            instrumentDivider()

            Instrument(
                label: "Needs you",
                value: "\(counts.blocked)",
                unit: "blocked",
                sub: counts.blocked > 0 ? "questions pending" : "all clear",
                dot: counts.blocked > 0 ? .blocked : .idle,
                attention: counts.blocked > 0
            )

            instrumentDivider()

            Instrument(
                label: "Up for review",
                value: "\(counts.review)",
                unit: "PRs",
                sub: "avg age 1h 12m",
                dot: .review,
                attention: false
            )

            instrumentDivider()

            Instrument(
                label: "Spend",
                value: String(format: "$%.2f", spend.today),
                unit: "today",
                sub: String(format: "$%.0f budget · %d%%",
                            spend.budget,
                            Int((spend.today / spend.budget * 100).rounded())),
                dot: .done,
                attention: false
            )

            instrumentDivider()

            ActivityCluster()
                .frame(maxWidth: .infinity)
                .padding(.leading, 22)
        }
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [p.paper2, p.paper], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private func instrumentDivider() -> some View {
        Hairline(axis: .vertical)
            .padding(.vertical, 4)
            .frame(width: Tokens.Hairline.width)
    }
}

// MARK: – Instrument cell

private struct Instrument: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let unit: String
    let sub: String
    let dot: AgentStatus
    let attention: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PulseDot(status: dot)
                Text(label.uppercased())
                    .font(SkogaFont.monoTiny(9.5))
                    .tracking(0.95)
            }
            .foregroundStyle(attention ? p.ember : p.inkFaint)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(SkogaFont.serifValue(26))
                    .foregroundStyle(attention ? p.ember : p.ink)
                Text(unit)
                    .font(SkogaFont.monoSmall(10.5))
                    .foregroundStyle(p.inkMute)
            }
            .lineLimit(1)

            Text(sub)
                .font(SkogaFont.monoSmall(10.5))
                .foregroundStyle(p.inkMute)
        }
        .padding(.horizontal, 22)
    }
}

// MARK: – Activity cluster

private struct ActivityCluster: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Guild pulse · last 30m".uppercased())
                    .font(SkogaFont.monoTiny(9.5))
                    .tracking(0.95)
                    .foregroundStyle(p.inkFaint)
                Spacer()
                Text("tokens/min")
                    .font(SkogaFont.monoTiny(9.5))
                    .foregroundStyle(p.inkMute)
            }
            ActivityBars(data: state.activity)
        }
    }
}

// MARK: – Helpers

private extension Int {
    func formattedWithSeparators() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
