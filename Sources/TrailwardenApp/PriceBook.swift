// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// What Settings › Prices shows and changes: the models the agents used, the
/// price each one is estimated at, the reader's own prices, and the manual
/// update of the published list.
@MainActor
final class PriceBook: ObservableObject {
    enum UpdateState: Equatable {
        case idle
        case checking
        case updated(String)
        case alreadyCurrent
        case failed
    }

    struct Row: Identifiable, Equatable {
        /// The model id as the price table keys it.
        let id: String
        let agents: [Agent]
        let tokens: Int
    }

    @Published private(set) var table = PriceTable.builtIn
    @Published private(set) var rows: [Row] = []
    @Published private(set) var problem: String?
    @Published private(set) var updateState: UpdateState = .idle

    /// Called after a price or the list changed, so the usage screen can redo
    /// its estimate.
    var onChange: (() -> Void)?

    var unpricedCount: Int {
        rows.count { table.price(for: $0.id) == nil }
    }

    var userCount: Int {
        rows.count { table.source(for: $0.id) == .user }
    }

    private let databaseURL: URL
    /// Models the reader typed in that no agent has used yet.
    private var added: [String] = []
    private var used: [Row] = []

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func reload() async {
        let database = databaseURL
        let (loaded, usage) = await Task.detached(priority: .utility) { () -> (
            PriceTable.Loaded,
            [ModelUsage]) in
            let since = Date().addingTimeInterval(-90 * 86400)
            let usage = (try? EventStore(url: database).tokenCountsByModel(since: since)) ?? []
            return (PriceTable.load(), usage)
        }.value
        var tokens: [String: Int] = [:]
        var agents: [String: Set<Agent>] = [:]
        for row in usage {
            let key = PriceTable.normalize(row.model)
            tokens[key] = tokens[key, default: 0].saturatingAdd(row.tokens.processed)
            agents[key, default: []].insert(row.agent)
        }
        used = tokens.keys.map { key in
            Row(
                id: key,
                agents: agents[key, default: []].sorted { $0.rawValue < $1.rawValue },
                tokens: tokens[key] ?? 0)
        }
        table = loaded.table
        problem = loaded.problem
        for key in loaded.userPrices.keys.map(PriceTable.normalize) where !added.contains(key) {
            added.append(key)
        }
        arrange()
    }

    /// Unpriced models first (they are the ones to fill in), then the busiest.
    private func arrange() {
        var all = used
        for key in added where !all.contains(where: { $0.id == key }) {
            all.append(Row(id: key, agents: [], tokens: 0))
        }
        rows = all.sorted { lhs, rhs in
            let lhsUnpriced = table.price(for: lhs.id) == nil
            let rhsUnpriced = table.price(for: rhs.id) == nil
            if lhsUnpriced != rhsUnpriced {
                return lhsUnpriced
            }
            if lhs.tokens != rhs.tokens {
                return lhs.tokens > rhs.tokens
            }
            return lhs.id < rhs.id
        }
    }

    /// A row for a model no agent has used yet, to price ahead of time.
    func add(_ model: String) {
        let key = PriceTable.normalize(model)
        guard !key.isEmpty, !rows.contains(where: { $0.id == key }) else { return }
        added.append(key)
        arrange()
    }

    /// Saves the reader's price for a model; `nil` goes back to the list price.
    func save(_ price: ModelPrice?, for model: String) async {
        do {
            try PriceTable.setUserPrice(price, for: model, at: PriceTable.userPricesURL())
            problem = nil
        } catch {
            let plain = L(.priceSaveFailed)
            problem = TechnicalDetails.isOn ? "\(plain)\n\(String(describing: error))" : plain
        }
        await reload()
        onChange?()
    }

    /// Reads the published list (the one network call besides the app update
    /// check) and keeps it only when it is newer than the list in use.
    func checkForNewList(using updates: UpdateChecker) async {
        guard updateState != .checking else { return }
        updateState = .checking
        do {
            let data = try await updates.downloadPriceList()
            let outcome = try PriceTable.installPublished(
                data,
                at: PriceTable.publishedListURL(),
                current: table)
            switch outcome {
            case let .updated(date): updateState = .updated(date)
            case .alreadyCurrent: updateState = .alreadyCurrent
            }
        } catch {
            updateState = .failed
        }
        await reload()
        onChange?()
    }
}
