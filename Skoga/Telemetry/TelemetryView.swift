import SwiftUI

struct TelemetryView: View {
    @Environment(\.palette) private var p
    @Environment(AppState.self) private var state

    struct ModelStat {
        let model: String
        let runs: Int
        let cost: Double
        let tokens: Int
    }

    private var totalSpend: Double {
        state.agents.reduce(0) { $0 + $1.cost }
    }
    private var totalTokens: Int {
        state.agents.reduce(0) { $0 + $1.tokens }
    }
    private var blockedRate: Int {
        let attn = state.agents.filter(\.attn).count
        guard !state.agents.isEmpty else { return 0 }
        return Int(Double(attn) / Double(state.agents.count) * 100)
    }
    private var attnCount: Int { state.agents.filter(\.attn).count }

    private var byModel: [ModelStat] {
        var dict: [String: ModelStat] = [:]
        for a in state.agents {
            let s = dict[a.model] ?? ModelStat(model: a.model, runs: 0, cost: 0, tokens: 0)
            dict[a.model] = ModelStat(model: a.model, runs: s.runs + 1, cost: s.cost + a.cost, tokens: s.tokens + a.tokens)
        }
        return dict.values.sorted { $0.runs > $1.runs }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Telemetry · today")
                    .font(SkogaFont.serifTitle(26))
                    .foregroundStyle(p.ink)
                Text("Spend, throughput, and which agents keep getting stuck.")
                    .font(SkogaFont.body(13))
                    .foregroundStyle(p.inkMute)
                    .padding(.top, 6).padding(.bottom, 22)

                heroRow.padding(.bottom, 22)

                Text("BY MODEL")
                    .font(SkogaFont.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(p.inkFaint)
                    .padding(.bottom, 10)

                modelTable
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 28)
        }
        .background(p.paper)
    }

    private var heroRow: some View {
        HStack(spacing: 14) {
            heroCard(label: "spend",
                     value: String(format: "$%.2f", totalSpend),
                     sub: String(format: "of $40.00 budget · %d%%", Int(totalSpend / 40 * 100)))
            heroCard(label: "tokens",
                     value: String(format: "%.2fM", Double(totalTokens) / 1_000_000),
                     sub: "\(state.agents.count) agents · avg \(state.agents.isEmpty ? 0 : totalTokens / state.agents.count / 1000)k each")
            heroCard(label: "blocked rate",
                     value: "\(blockedRate)%",
                     sub: "\(attnCount) of \(state.agents.count) need you")
        }
    }

    private func heroCard(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(SkogaFont.monoTiny(9.5))
                .tracking(0.95)
                .foregroundStyle(p.inkFaint)
            Text(value)
                .font(SkogaFont.serifValue(32))
                .foregroundStyle(p.ink)
            Text(sub)
                .font(SkogaFont.monoSmall(11))
                .foregroundStyle(p.inkMute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private var modelTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Hairline()
            ForEach(byModel, id: \.model) { stat in
                tableRow(stat)
                Hairline()
            }
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("Runs").frame(width: 80, alignment: .trailing)
            Text("Tokens").frame(width: 100, alignment: .trailing)
            Text("Spend").frame(width: 100, alignment: .trailing)
            Text("$/run").frame(width: 100, alignment: .trailing)
        }
        .font(SkogaFont.monoTiny(10))
        .tracking(0.8)
        .foregroundStyle(p.inkFaint)
        .textCase(.uppercase)
        .padding(.horizontal, 4).padding(.vertical, 10)
    }

    private func tableRow(_ s: ModelStat) -> some View {
        HStack {
            Text(s.model)
                .font(SkogaFont.mono(12))
                .foregroundStyle(p.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(s.runs)")
                .font(SkogaFont.mono(12))
                .foregroundStyle(p.ink)
                .frame(width: 80, alignment: .trailing)
            Text("\(s.tokens / 1000)k")
                .font(SkogaFont.mono(12))
                .foregroundStyle(p.ink)
                .frame(width: 100, alignment: .trailing)
            Text(String(format: "$%.2f", s.cost))
                .font(SkogaFont.mono(12))
                .foregroundStyle(p.ink)
                .frame(width: 100, alignment: .trailing)
            Text(String(format: "$%.2f", s.runs == 0 ? 0 : s.cost / Double(s.runs)))
                .font(SkogaFont.mono(12))
                .foregroundStyle(p.ink)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 4).padding(.vertical, 12)
    }
}
