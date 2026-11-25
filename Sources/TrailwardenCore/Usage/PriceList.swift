// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// A price list on disk. The same shape serves the list published in the
/// repository (`prices.json` at its root), the downloaded copy of it, and the
/// reader's own prices:
///
/// ```json
/// {
///   "asOf": "2026-11-20",
///   "models": {
///     "gpt-6-sol": { "input": 2, "output": 10, "cacheRead": 0.2, "cacheWrite": 2.5 },
///     "some-model:beta": { "free": true }
///   }
/// }
/// ```
///
/// Dollars per million tokens. A missing rate reads as 0; `"free": true` is a
/// model that costs nothing. `asOf` is required only of a published list.
public struct PriceList: Sendable, Equatable {
    public var asOf: String
    public var prices: [String: ModelPrice]

    public init(asOf: String = "", prices: [String: ModelPrice]) {
        self.asOf = asOf
        self.prices = prices
    }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case notAPriceList
        case missingDate
        case empty
        case badRate(String)
        case futureDate(String)

        public var description: String {
            switch self {
            case .notAPriceList: "not a price list"
            case .missingDate: "the list has no asOf date"
            case .empty: "the list has no models"
            case let .badRate(model): "an impossible rate for \(model)"
            case let .futureDate(date): "the list is dated in the future (\(date))"
            }
        }
    }

    private struct File: Codable {
        var asOf: String?
        var models: [String: Entry]
    }

    private struct Entry: Codable {
        var input: Double?
        var output: Double?
        var cacheRead: Double?
        var cacheWrite: Double?
        var free: Bool?
    }

    public static func decode(_ data: Data) throws -> PriceList {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw Problem.notAPriceList
        }
        var prices: [String: ModelPrice] = [:]
        for (model, entry) in file.models {
            let price = entry.free == true ? ModelPrice.free : ModelPrice(
                input: entry.input ?? 0,
                output: entry.output ?? 0,
                cacheRead: entry.cacheRead ?? 0,
                cacheWrite: entry.cacheWrite ?? 0)
            try check(price, for: model)
            prices[model] = price
        }
        return PriceList(asOf: file.asOf ?? "", prices: prices)
    }

    /// No provider charges a negative or a four-figure rate per million tokens;
    /// such a number is a typo or a tampered file.
    public static let maxRate = 1000.0

    /// Throws `badRate` unless every rate is finite, not negative and below
    /// `maxRate`. Used on reading *and* on saving, so a price the reader typed
    /// can never make their own file unreadable.
    public static func check(_ price: ModelPrice, for model: String) throws {
        let rates = [price.input, price.output, price.cacheRead, price.cacheWrite]
        guard rates.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < maxRate }) else {
            throw Problem.badRate(model)
        }
    }

    /// A list date is usable when it is a real `yyyy-MM-dd` day and not later
    /// than tomorrow (UTC), so a broken or tampered date cannot block every
    /// later list from looking newer.
    static func isUsableDate(_ text: String, now: Date = Date()) -> Bool {
        guard let day = PriceTable.day(text) else { return false }
        return day.timeIntervalSince(now) <= 86400
    }

    public func encoded() throws -> Data {
        let models = prices.mapValues { price in
            price.isFree ? Entry(free: true) : Entry(
                input: price.input,
                output: price.output,
                cacheRead: price.cacheRead,
                cacheWrite: price.cacheWrite)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(File(asOf: asOf.isEmpty ? nil : asOf, models: models))
    }

    /// The list in a file, or `nil` when there is no file.
    static func read(_ url: URL) throws -> PriceList? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(Data(contentsOf: url))
    }

    /// Checks a downloaded list before it is kept: it must parse, carry a date
    /// and price at least one model.
    public static func validatePublished(_ data: Data, now: Date = Date()) throws -> PriceList {
        let list = try decode(data)
        guard PriceTable.day(list.asOf) != nil else { throw Problem.missingDate }
        guard isUsableDate(list.asOf, now: now) else { throw Problem.futureDate(list.asOf) }
        guard !list.prices.isEmpty else { throw Problem.empty }
        return list
    }
}

public extension PriceTable {
    /// `~/Library/Application Support/Trailwarden/prices.json`: the reader's own.
    static func userPricesURL() throws -> URL {
        try RulePreferences.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("prices.json")
    }

    /// `~/Library/Application Support/Trailwarden/prices-published.json`: the
    /// last list downloaded with "Update prices".
    static func publishedListURL() throws -> URL {
        try RulePreferences.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("prices-published.json")
    }

    /// Sets (or, with `nil`, removes) the reader's own price for a model.
    static func setUserPrice(_ price: ModelPrice?, for model: String, at url: URL) throws {
        let key = normalize(model)
        guard !key.isEmpty else { return }
        if let price {
            try PriceList.check(price, for: key)
        }
        var list = try PriceList.read(url) ?? PriceList(prices: [:])
        list.prices = Dictionary(
            list.prices.map { (normalize($0.key), $0.value) },
            uniquingKeysWith: { _, last in last })
        list.prices[key] = price
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try list.encoded().write(to: url, options: .atomic)
    }

    enum PublishedOutcome: Equatable, Sendable {
        /// The download is newer than what was in use, and is now used.
        case updated(String)
        /// What is in use is already as new as the download.
        case alreadyCurrent(String)
    }

    /// Keeps a downloaded list when it is newer than the one in use. Nothing is
    /// written for an older or equal list, so a stale mirror cannot roll prices
    /// back.
    static func installPublished(
        _ data: Data,
        at url: URL,
        current: PriceTable,
        now: Date = Date()) throws -> PublishedOutcome
    {
        let list = try PriceList.validatePublished(data, now: now)
        guard list.asOf > current.asOf else { return .alreadyCurrent(current.asOf) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return .updated(list.asOf)
    }

    /// The built-in list in the published shape, for writing `prices.json`.
    static var builtInList: PriceList {
        PriceList(asOf: builtIn.asOf, prices: builtIn.prices)
    }
}
