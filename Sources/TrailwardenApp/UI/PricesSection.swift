// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// Settings › Prices: where the list comes from, how many models still need a
/// price, and the button that opens the price window. The published list is
/// fetched only from the "Update prices" button.
struct PricesSection: View {
    @ObservedObject var book: PriceBook
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(.pricesSection))
            PriceListLine(book: book, updates: updates)
            HStack(spacing: 10) {
                Button(L(.editPrices)) {
                    openWindow(id: PricesWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Text(Lf(.pricesSummary, [book.rows.count, book.unpricedCount, book.userCount]))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(book.unpricedCount > 0 ? Tokens.Palette.accent : Tokens.Palette
                        .secondary)
            }
            Text(L(.pricesHint))
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await book.reload() }
    }
}

/// The price window: every model, a search field, and the editors.
struct PricesWindow: View {
    static let id = "prices"

    @ObservedObject var book: PriceBook
    @ObservedObject var updates: UpdateChecker
    @State private var search = ""
    @State private var onlyUnpriced = false
    @State private var newModel = ""

    private var shown: [PriceBook.Row] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        return book.rows.filter { row in
            if onlyUnpriced, book.table.price(for: row.id) != nil {
                return false
            }
            guard !term.isEmpty else { return true }
            return row.id.contains(term)
                || row.agents.contains { EventFormatting.agentLabel($0).lowercased().contains(term) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L(.pricesSection))
                    .font(Tokens.Typography.serif(18, weight: .semibold))
                PriceListLine(book: book, updates: updates)
                HStack(spacing: 12) {
                    TextField(L(.searchModels), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                    Toggle(L(.onlyUnpriced), isOn: $onlyUnpriced)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Text(Lf(.pricesSummary, [book.rows.count, book.unpricedCount, book.userCount]))
                        .font(Tokens.Typography.mono(9.5))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
                .controlSize(.small)
            }
            Hairline()
            PriceColumns()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { row in
                        PriceRowEditor(
                            row: row,
                            price: book.table.price(for: row.id),
                            source: book.table.source(for: row.id))
                        { price in
                            Task { await book.save(price, for: row.id) }
                        }
                    }
                    if shown.isEmpty {
                        Text(book.rows.isEmpty ? L(.noPriceModels) : Lf(.noPriceMatches, [search]))
                            .font(Tokens.Typography.text(10))
                            .foregroundStyle(Tokens.Palette.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Hairline()
            addRow
            if let problem = book.problem {
                Text(problem)
                    .font(Tokens.Typography.text(9.5))
                    .foregroundStyle(Tokens.Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 420)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
        .task { await book.reload() }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField(L(.addModelPlaceholder), text: $newModel)
                .textFieldStyle(.roundedBorder)
                .font(Tokens.Typography.mono(10))
                .frame(width: 280)
                .onSubmit(add)
            Button(L(.addModel), action: add)
                .disabled(newModel.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.small)
    }

    private func add() {
        let key = PriceTable.normalize(newModel)
        book.add(newModel)
        newModel = ""
        // Show the new row even if a search or the filter would hide it.
        search = key
        onlyUnpriced = false
    }
}

/// The list's date and source, the "Update prices" button and its outcome.
private struct PriceListLine: View {
    @ObservedObject var book: PriceBook
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(Lf(
                    book.table.usesPublishedList ? .priceListDownloaded : .priceListBuiltIn,
                    [book.table.asOf]))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(Tokens.Palette.secondary)
                Button(book.updateState == .checking ? L(.checkingPrices) : L(.checkPrices)) {
                    Task { await book.checkForNewList(using: updates) }
                }
                .disabled(book.updateState == .checking)
                if let status {
                    Text(status)
                        .font(Tokens.Typography.mono(9.5))
                        .foregroundStyle(book.updateState == .failed ? Tokens.Palette.accent : Tokens.Palette
                            .secondary)
                }
            }
            if book.table.isStale() {
                Text(L(.pricesStale))
                    .font(Tokens.Typography.text(9.5, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var status: String? {
        switch book.updateState {
        case .idle, .checking: nil
        case let .updated(date): Lf(.pricesUpdated, [date])
        case .alreadyCurrent: L(.pricesCurrent)
        case .failed: L(.pricesCheckFailed)
        }
    }
}

private enum PriceLayout {
    static let model: CGFloat = 210
    static let rate: CGFloat = 86
}

private struct PriceColumns: View {
    var body: some View {
        HStack(spacing: 6) {
            Text(L(.priceModel)).frame(width: PriceLayout.model, alignment: .leading)
            ForEach(
                [UIString.priceInput, .priceOutput, .priceCacheRead, .priceCacheWrite],
                id: \.self)
            { key in
                Text(L(key)).frame(width: PriceLayout.rate, alignment: .leading)
            }
            Spacer()
        }
        .font(Tokens.Typography.text(9, weight: .semibold))
        .foregroundStyle(Tokens.Palette.secondary)
        .lineLimit(1)
    }
}

/// One model: four rates, "free", and save or go back to the list price. The
/// fields hold a draft; nothing is written until Save.
private struct PriceRowEditor: View {
    let row: PriceBook.Row
    let price: ModelPrice?
    let source: PriceSource?
    let onSave: (ModelPrice?) -> Void

    @State private var input: Double?
    @State private var output: Double?
    @State private var cacheRead: Double?
    @State private var cacheWrite: Double?
    @State private var free = false

    private var draft: ModelPrice {
        free ? .free : ModelPrice(
            input: max(0, input ?? 0),
            output: max(0, output ?? 0),
            cacheRead: max(0, cacheRead ?? 0),
            cacheWrite: max(0, cacheWrite ?? 0))
    }

    private var changed: Bool {
        guard let price else { return free || [input, output, cacheRead, cacheWrite].contains { $0 != nil } }
        return draft != price
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.id)
                    .font(Tokens.Typography.mono(10.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(caption)
                    .font(Tokens.Typography.text(9))
                    .foregroundStyle(price == nil ? Tokens.Palette.accent : Tokens.Palette.secondary)
                    .lineLimit(1)
            }
            .frame(width: PriceLayout.model, alignment: .leading)
            .help(row.id)
            field($input)
            field($output)
            field($cacheRead)
            field($cacheWrite)
            Toggle(L(.priceFreeToggle), isOn: $free)
                .toggleStyle(.checkbox)
                .font(Tokens.Typography.text(10))
            Spacer(minLength: 6)
            if changed {
                Button(L(.priceSave)) { onSave(draft) }
            }
            if source == .user {
                Button(L(.priceReset)) { onSave(nil) }
            }
        }
        .controlSize(.small)
        .onAppear(perform: fill)
        .onChange(of: price) { _, _ in fill() }
    }

    private func field(_ value: Binding<Double?>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0 ... 4)), prompt: Text("—"))
            .textFieldStyle(.roundedBorder)
            .font(Tokens.Typography.mono(10))
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            .frame(width: PriceLayout.rate)
            .disabled(free)
    }

    /// Where the price comes from, who used the model, and how much.
    private var caption: String {
        var parts: [String] = []
        switch (price, source) {
        case (nil, _): parts.append(L(.priceUnknown))
        case (.some(.free), nil): parts.append(L(.priceFree)) // free by its name
        case (_, .user?): parts.append(L(.priceSourceUser))
        case (_, .published?): parts.append(L(.priceSourcePublished))
        default: parts.append(L(.priceSourceBuiltIn))
        }
        if !row.agents.isEmpty {
            parts.append(row.agents.map(EventFormatting.agentLabel).joined(separator: ", "))
        }
        if row.tokens > 0 {
            parts.append(UsageView.tokens(row.tokens))
        }
        return parts.joined(separator: " · ")
    }

    private func fill() {
        free = price?.isFree ?? false
        let shown = price?.isFree == true ? nil : price
        input = shown?.input
        output = shown?.output
        cacheRead = shown?.cacheRead
        cacheWrite = shown?.cacheWrite
    }
}
