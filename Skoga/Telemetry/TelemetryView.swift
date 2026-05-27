import SwiftUI

struct TelemetryView: View {
    @Environment(\.palette) private var p
    @Environment(RosterState.self) private var roster

    /// Daily cap, bound to the Settings → Budgets slider's storage key so
    /// the hero card redraws live when the user drags the slider — the
    /// Cockpit "Spend" cell binds to the same key for the same reason.
    @AppStorage(BudgetPrefs.Cap.daily) private var dailyBudget: Double = BudgetPrefs.Cap.dailyDefault

    struct ModelStat {
        let model: String
        let runs: Int
        let cost: Double
        let tokens: Int
    }

    private var totalSpend: Double {
        roster.agents.reduce(0) { $0 + $1.cost }
    }
    private var totalTokens: Int {
        roster.agents.reduce(0) { $0 + $1.tokens }
    }
    private var blockedRate: Int {
        let attn = roster.agents.filter(\.attn).count
        guard !roster.agents.isEmpty else { return 0 }
        return Int(Double(attn) / Double(roster.agents.count) * 100)
    }
    private var attnCount: Int { roster.agents.filter(\.attn).count }

    /// Roll up runs/tokens/spend per model across the roster. Prefer
    /// the daemon's per-message `usageByModel` breakdown (which can
    /// attribute a single session to multiple models — e.g. a Sonnet
    /// session that planned with Opus) over `Agent.model` (the launch
    /// pin, only one string). Falls back to the launch pin when the
    /// daemon hasn't computed usage for that session yet (pre-#86) so
    /// the table still renders something for mock seeds.
    ///
    /// `runs` counts each session once per distinct model it touched
    /// — so a session that used both Opus and Sonnet shows up as one
    /// run in each model's row. `$/run` then reads as "average cost
    /// per session-that-touched-this-model", matching how the field
    /// is interpreted elsewhere in the issue.
    private var byModel: [ModelStat] {
        var dict: [String: ModelStat] = [:]
        for a in roster.agents {
            if a.usageByModel.isEmpty {
                let s = dict[a.model] ?? ModelStat(model: a.model, runs: 0, cost: 0, tokens: 0)
                dict[a.model] = ModelStat(
                    model: a.model,
                    runs: s.runs + 1,
                    cost: s.cost + a.cost,
                    tokens: s.tokens + a.tokens
                )
            } else {
                for (model, mu) in a.usageByModel {
                    let s = dict[model] ?? ModelStat(model: model, runs: 0, cost: 0, tokens: 0)
                    dict[model] = ModelStat(
                        model: model,
                        runs: s.runs + 1,
                        cost: s.cost + mu.cost,
                        tokens: s.tokens + mu.tokens
                    )
                }
            }
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
                     sub: String(format: "of $%.2f budget · %d%%",
                                 dailyBudget,
                                 dailyBudget > 0 ? Int((totalSpend / dailyBudget * 100).rounded()) : 0))
            heroCard(label: "tokens",
                     value: String(format: "%.2fM", Double(totalTokens) / 1_000_000),
                     sub: "\(roster.agents.count) agents · avg \(roster.agents.isEmpty ? 0 : totalTokens / roster.agents.count / 1000)k each")
            heroCard(label: "blocked rate",
                     value: "\(blockedRate)%",
                     sub: "\(attnCount) of \(roster.agents.count) need you")
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
