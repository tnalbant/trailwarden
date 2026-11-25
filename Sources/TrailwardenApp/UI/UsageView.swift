// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Charts
import SwiftUI
import TrailwardenCore

/// Where the tokens went, per day, per agent and per model. The counts come
/// from the transcripts; the dollars are an estimate at bundled pay-as-you-go
/// API prices, labelled as such, and a model without a price shows none.
struct UsageView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage(TechnicalDetails.storageKey) private var technical = false
    @ObservedObject var model: AppModel
    @State private var days = 30
    private let ranges = [7, 30, 90]

    private var total: Int {
        model.usage.values.reduce(0) { $0.saturatingAdd($1.processed) }
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
                models
                Hairline()
                footnote
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
        .onAppear { Task { await model.loadUsage(days: days) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L(.windowUsage))
                .font(Tokens.Typography.font(.title, weight: .semibold))
            Text(Lf(.usageSummary, [days, Self.tokens(total), Lf(.activeDays, [model.dailyUsage.count])]))
                .font(Tokens.Typography.font(.code))
                .foregroundStyle(Tokens.Palette.secondary)
            if model.costEstimate.pricedTokens > 0 {
                Text(Lf(.estimatedCost, [Self.dollars(model.costEstimate.dollars)]))
                    .font(Tokens.Typography.font(.code, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.accentText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Picker(L(.rangePickerLabel), selection: $days) {
                ForEach(ranges, id: \.self) { value in
                    Text(Lf(.daysLeft, [value])).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .onChange(of: days) { _, value in
                Task { await model.loadUsage(days: value) }
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(.dailyTokens))
            if model.dailyUsage.isEmpty {
                Text(L(.noTokenData))
                    .font(Tokens.Typography.font(.body))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                Chart(model.dailyUsage) { day in
                    BarMark(
                        x: .value(L(.axisDay), day.day, unit: .day),
                        y: .value("Token", day.tokens))
                        .foregroundStyle(Tokens.Palette.accent.opacity(0.85))
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(2, model.dailyUsage.count / 4))) { _ in
                        AxisGridLine().foregroundStyle(Tokens.Palette.hairline)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                            .font(Tokens.Typography.font(.caption))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let tokens = value.as(Int.self) {
                                Text(UsageView.tokens(tokens)).font(Tokens.Typography.font(.codeSmall))
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
            SectionLabel(text: L(.byAgent), trailing: L(.processedTokens))
            ForEach(Agent.allCases, id: \.self) { agent in
                let totals = model.usage[agent]
                if let totals, totals.processed > 0 || totals.peakContext > 0 {
                    HStack(spacing: 10) {
                        Text(EventFormatting.agentLabel(agent))
                            .font(Tokens.Typography.font(.body, weight: .medium))
                            .fixedSize()
                            .frame(minWidth: Tokens.Metrics.scaled(92), alignment: .leading)
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
                            .font(Tokens.Typography.font(.code))
                            .fixedSize()
                            .frame(minWidth: Tokens.Metrics.scaled(96), alignment: .trailing)
                        if technical {
                            Text(Lf(.counterCount, [totals.events]))
                                .font(Tokens.Typography.font(.caption))
                                .foregroundStyle(Tokens.Palette.secondary)
                                .fixedSize()
                                .frame(minWidth: Tokens.Metrics.scaled(72), alignment: .trailing)
                        }
                    }
                }
            }
            if model.usage.values.allSatisfy({ $0.processed == 0 && $0.peakContext == 0 }) {
                Text(L(.noCounterData))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.byModel), trailing: L(.apiEquivalent))
            if model.modelUsage.isEmpty {
                Text(L(.noCounterData))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            ForEach(model.modelUsage) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.model)
                            .font(Tokens.Typography.font(.code, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(EventFormatting.agentLabel(row.agent))
                            .font(Tokens.Typography.font(.caption))
                            .foregroundStyle(Tokens.Palette.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(Self.tokens(row.tokens.processed))
                        .font(Tokens.Typography.font(.code))
                        .fixedSize()
                        .frame(minWidth: Tokens.Metrics.scaled(80), alignment: .trailing)
                    Text(priceLabel(row))
                        .font(Tokens.Typography.font(.code, weight: .semibold))
                        .foregroundStyle(model.prices.price(for: row.model) == nil
                            ? Tokens.Palette.secondary : Tokens.Palette.ink)
                        .fixedSize()
                        .frame(minWidth: Tokens.Metrics.scaled(88), alignment: .trailing)
                }
                .help(technical ? breakdown(row.tokens) : "")
            }
            if model.costEstimate.unpricedTokens > 0 {
                Text(Lf(.unpricedNote, [
                    Self.tokens(model.costEstimate.unpricedTokens),
                    model.costEstimate.unpricedModels.count
                ]))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
            }
        }
    }

    private func priceLabel(_ row: ModelUsage) -> String {
        guard let price = model.prices.price(for: row.model) else { return L(.priceUnknown) }
        if price.isFree {
            return L(.priceFree)
        }
        return Self.dollars(price.cost(of: row.tokens))
    }

    /// The split behind a row, on hover: where the tokens (and the money) went.
    private func breakdown(_ tokens: TokenCount) -> String {
        [
            "\(L(.tokenInput)) \(Self.tokens(tokens.input))",
            "\(L(.tokenCacheRead)) \(Self.tokens(tokens.cacheRead))",
            "\(L(.tokenCacheWrite)) \(Self.tokens(tokens.cacheWrite))",
            "\(L(.tokenOutput)) \(Self.tokens(tokens.output))",
            tokens.reasoning > 0 ? "\(L(.tokenReasoning)) \(Self.tokens(tokens.reasoning))" : nil
        ].compactMap(\.self).joined(separator: " · ")
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: L(.noteTitle))
            Text(L(.usageNote))
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Lf(.priceNote, [model.prices.asOf]))
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.prices.isStale() {
                Text(L(.pricesStale))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.priceFileError {
                Text(Lf(.priceFileError, [error]))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// $1,234 above a hundred dollars, cents below, and "< $0.01" for crumbs.
    static func dollars(_ value: Double) -> String {
        switch value {
        case 100...:
            "$" + value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
        case 0.01...:
            "$" + value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
        case 0:
            "$0"
        default:
            "< $0.01"
        }
    }

    /// 1.2M, 34.5K — the way Apple formats large counts in a label.
    static func tokens(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...:
            String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.1fM", Double(value) / 1_000_000)
        case 1000...:
            String(format: "%.1fK", Double(value) / 1000)
        default:
            "\(value)"
        }
    }

    private func share(_ totals: TokenTotals) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(totals.processed) / CGFloat(total)
    }
}
