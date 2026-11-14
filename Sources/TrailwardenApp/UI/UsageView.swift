// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Charts
import SwiftUI
import TrailwardenCore

/// Where the tokens went, per day and per agent. The numbers come from the
/// transcripts; no price is shown because a token's price depends on the plan,
/// the model and the day, and a wrong number is worse than none.
struct UsageView: View {
    @ObservedObject var model: AppModel

    private var total: Int {
        model.usage.values.reduce(0) { $0 + $1.processed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Hairline()
                chart
                Hairline()
                agents
                Hairline()
                footnote
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .onAppear { Task { await model.loadUsage() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Kullanım")
                .font(Tokens.Typography.serif(19, weight: .semibold))
            Text("Son 30 gün · \(Self.tokens(total)) token · \(model.dailyUsage.count) gün")
                .font(Tokens.Typography.mono(10))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Günlük token")
            if model.dailyUsage.isEmpty {
                Text("Henüz token kaydı yok. Ajanlar bir oturumda sayaç yazdığında burada görünür.")
                    .font(Tokens.Typography.text(11))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                Chart(model.dailyUsage) { day in
                    BarMark(
                        x: .value("Gün", day.day, unit: .day),
                        y: .value("Token", day.tokens)
                    )
                    .foregroundStyle(Tokens.Palette.accent.opacity(0.85))
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(2, model.dailyUsage.count / 4))) { _ in
                        AxisGridLine().foregroundStyle(Tokens.Palette.hairline)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                            .font(Tokens.Typography.text(9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let tokens = value.as(Int.self) {
                                Text(UsageView.tokens(tokens)).font(Tokens.Typography.mono(8.5))
                            }
                        }
                        .foregroundStyle(Tokens.Palette.secondary)
                        AxisGridLine().foregroundStyle(Tokens.Palette.hairline)
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Ajana göre", trailing: "token")
            ForEach(Agent.allCases, id: \.self) { agent in
                let totals = model.usage[agent]
                if let totals, totals.processed > 0 || totals.peakContext > 0 {
                    HStack(spacing: 10) {
                        Text(EventFormatting.agentLabel(agent))
                            .font(Tokens.Typography.text(11.5, weight: .medium))
                            .frame(width: 92, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Tokens.Palette.hairline)
                                Capsule()
                                    .fill(Tokens.Palette.accent)
                                    .frame(width: max(3, geometry.size.width * share(totals)))
                            }
                        }
                        .frame(height: 6)
                        Text(Self.tokens(totals.processed))
                            .font(Tokens.Typography.mono(10))
                            .frame(width: 96, alignment: .trailing)
                        Text("\(totals.events) sayaç")
                            .font(Tokens.Typography.text(9.5))
                            .foregroundStyle(Tokens.Palette.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Not")
            Text("Sayılar ajanların kendi transkriptlerine yazdığı sayaçlardan toplanır. Fiyat gösterilmez: aynı token, plana ve modele göre farklı para eder.")
                .font(Tokens.Typography.text(10))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 1.2M, 34.5K — the way Apple formats large counts in a label.
    static func tokens(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    private func share(_ totals: TokenTotals) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(totals.processed) / CGFloat(total)
    }
}
