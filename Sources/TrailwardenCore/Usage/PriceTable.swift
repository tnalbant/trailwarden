// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// What one million tokens of each kind cost on a provider's pay-as-you-go API,
/// in US dollars.
public struct ModelPrice: Codable, Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public static let free = ModelPrice(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)

    public var isFree: Bool {
        self == .free
    }

    /// The dollars a count would have cost at these rates.
    public func cost(of count: TokenCount) -> Double {
        (Double(count.input) * input
            + Double(count.output) * output
            + Double(count.cacheRead) * cacheRead
            + Double(count.cacheWrite) * cacheWrite) / 1_000_000
    }
}

/// Where the price the table uses for a model came from.
public enum PriceSource: String, Sendable {
    /// The list compiled into this release.
    case builtIn
    /// The newer list downloaded with "Update prices".
    case published
    /// A price the reader entered; nothing overwrites it.
    case user
}

/// The price list Trailwarden estimates with, in three layers, each on top of
/// the one before:
///
/// 1. the list compiled into the release (`builtIn`),
/// 2. a newer list downloaded on request from the project's repository,
/// 3. the reader's own prices, entered in Settings.
///
/// Every figure it produces is an estimate: what the same tokens would have
/// cost on the provider's API, not what a subscription actually charged.
public struct PriceTable: Sendable {
    /// The date of the list in use: the downloaded one when it is newer.
    public private(set) var asOf: String
    public private(set) var prices: [String: ModelPrice]
    public private(set) var sources: [String: PriceSource]

    public init(asOf: String, prices: [String: ModelPrice]) {
        self.asOf = asOf
        self.prices = Dictionary(
            prices.map { (Self.normalize($0.key), $0.value) },
            uniquingKeysWith: { _, last in last })
        sources = self.prices.mapValues { _ in .builtIn }
    }

    /// True when the list in use comes from a download rather than the release.
    public var usesPublishedList: Bool {
        sources.values.contains(.published)
    }

    /// The price for a model id as an agent wrote it, or `nil` when the table
    /// does not know it. Free routes (`…:free`, `…-free`) cost nothing unless a
    /// price was entered for that exact id.
    public func price(for model: String) -> ModelPrice? {
        lookup(model)?.price
    }

    /// Which layer the price for a model comes from; `nil` when it has none or
    /// when only its `:free` name makes it free.
    public func source(for model: String) -> PriceSource? {
        lookup(model)?.key.flatMap { sources[$0] }
    }

    private func lookup(_ model: String) -> (key: String?, price: ModelPrice)? {
        let key = Self.normalize(model)
        if let exact = prices[key] {
            return (key, exact)
        }
        if Self.isFree(key) {
            return (nil, .free)
        }
        // A dated or suffixed id ("qwen3.7-plus-2026-05-26") takes the price of
        // the longest known id it extends, at a separator, never mid-word.
        return prices
            .filter { key.hasPrefix($0.key + "-") || key.hasPrefix($0.key + "@") }
            .max { $0.key.count < $1.key.count }
            .map { ($0.key, $0.value) }
    }

    /// The estimate for a set of per-model counts.
    public func estimate(_ usage: [ModelUsage]) -> CostEstimate {
        var estimate = CostEstimate()
        for row in usage {
            if let price = price(for: row.model) {
                estimate.dollars += price.cost(of: row.tokens)
                estimate.pricedTokens += row.tokens.processed
            } else {
                estimate.unpricedTokens += row.tokens.processed
                estimate.unpricedModels.insert(row.model)
            }
        }
        return estimate
    }

    /// Whether the list in use is older than `days`: prices move, and a reader
    /// should know when the one they see may have.
    public func isStale(now: Date = Date(), days: Int = 60) -> Bool {
        guard let date = Self.day(asOf) else { return false }
        return now.timeIntervalSince(date) > Double(days) * 86400
    }

    /// Lower case, without a router prefix: `openai/gpt-6-luna` and
    /// `GPT-6-Luna` are the same model for pricing.
    public static func normalize(_ model: String) -> String {
        let lowered = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.split(separator: "/").last.map(String.init) ?? lowered
    }

    static func isFree(_ key: String) -> Bool {
        key.hasSuffix(":free") || key.hasSuffix("-free")
    }

    static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    // MARK: - Layers

    mutating func apply(_ entries: [String: ModelPrice], as source: PriceSource) {
        for (model, price) in entries {
            let key = Self.normalize(model)
            guard !key.isEmpty else { continue }
            prices[key] = price
            sources[key] = source
        }
    }

    /// The table with every layer that is present, and what went wrong reading
    /// them. A broken file of the reader's own is reported, never silently
    /// ignored: a typo should not look like a price.
    public struct Loaded: Sendable {
        public var table: PriceTable
        public var userPrices: [String: ModelPrice]
        public var problem: String?
    }

    public static func load(
        user: URL? = try? userPricesURL(),
        published: URL? = try? publishedListURL()) -> Loaded
    {
        var table = builtIn
        var loaded = Loaded(table: table, userPrices: [:])
        if let published, let list = try? PriceList.read(published), list.asOf > table.asOf {
            table.apply(list.prices, as: .published)
            table.asOf = list.asOf
        }
        if let user {
            do {
                loaded.userPrices = try PriceList.read(user)?.prices ?? [:]
                table.apply(loaded.userPrices, as: .user)
            } catch {
                loaded.problem = String(describing: error)
            }
        }
        loaded.table = table
        return loaded
    }
}

/// The dollars a period's tokens would have cost, and what could not be priced.
public struct CostEstimate: Sendable, Equatable {
    public var dollars: Double = 0
    public var pricedTokens: Int = 0
    public var unpricedTokens: Int = 0
    public var unpricedModels: Set<String> = []

    public init() {}
}
