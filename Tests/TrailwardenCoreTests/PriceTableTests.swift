// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class PriceTableTests: XCTestCase {
    private let table = PriceTable(asOf: "2026-01-01", prices: [
        "model-a": ModelPrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5),
        "model-a-mini": ModelPrice(input: 1, output: 4, cacheRead: 0.1, cacheWrite: 1)
    ])

    func testEveryKindOfTokenHasItsOwnRate() {
        let price = ModelPrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5)
        let count = TokenCount(input: 1_000_000, output: 100_000, cacheRead: 10_000_000, cacheWrite: 200_000)
        // 2 + 1 + 2 + 0.5
        XCTAssertEqual(price.cost(of: count), 5.5, accuracy: 0.000001)
    }

    func testModelNamesAreMatchedLooselyButNeverMidWord() {
        XCTAssertEqual(table.price(for: "model-a")?.input, 2)
        XCTAssertEqual(table.price(for: "Model-A")?.input, 2, "case does not matter")
        XCTAssertEqual(table.price(for: "router/model-a")?.input, 2, "a router prefix is dropped")
        XCTAssertEqual(table.price(for: "model-a-2026-05-26")?.input, 2, "a dated id takes its base price")
        XCTAssertEqual(table.price(for: "model-a-mini-2026")?.input, 1, "the longest known id wins")
        XCTAssertNil(table.price(for: "model-ab"), "no match in the middle of a word")
        XCTAssertNil(table.price(for: "other"))
        XCTAssertEqual(table.price(for: "anything:free"), .free)
        XCTAssertEqual(table.price(for: "anything-free"), .free)
    }

    func testTheEstimateSaysWhatItCouldNotPrice() {
        let usage = [
            ModelUsage(agent: .codex, model: "model-a", tokens: TokenCount(input: 1_000_000)),
            ModelUsage(agent: .hermes, model: "mystery", tokens: TokenCount(input: 500)),
            ModelUsage(agent: .hermes, model: "x:free", tokens: TokenCount(input: 700))
        ]
        let estimate = table.estimate(usage)
        XCTAssertEqual(estimate.dollars, 2, accuracy: 0.000001)
        XCTAssertEqual(estimate.pricedTokens, 1_000_700)
        XCTAssertEqual(estimate.unpricedTokens, 500)
        XCTAssertEqual(estimate.unpricedModels, ["mystery"])
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json")
    }

    func testTheReadersOwnPricesWinAndCanBeFree() throws {
        let url = temporaryURL("prices")
        defer { try? FileManager.default.removeItem(at: url) }
        try PriceTable.setUserPrice(
            ModelPrice(input: 3, output: 9, cacheRead: 0, cacheWrite: 0), for: "My-Model", at: url)
        try PriceTable.setUserPrice(
            ModelPrice(input: 1, output: 1, cacheRead: 0, cacheWrite: 0),
            for: "claude-opus-5-5",
            at: url)
        try PriceTable.setUserPrice(.free, for: "router/gpt-6-luna", at: url)

        let loaded = PriceTable.load(user: url, published: nil)
        XCTAssertNil(loaded.problem)
        XCTAssertEqual(
            loaded.table.price(for: "my-model"),
            ModelPrice(input: 3, output: 9, cacheRead: 0, cacheWrite: 0))
        XCTAssertEqual(loaded.table.price(for: "claude-opus-5-5")?.input, 1)
        XCTAssertEqual(loaded.table.source(for: "claude-opus-5-5"), .user)
        XCTAssertEqual(loaded.table.price(for: "gpt-6-luna"), .free, "free is a price of its own")
        XCTAssertEqual(loaded.table.source(for: "claude-sonnet-5-5"), .builtIn, "the rest stays")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("\"free\" : true"))

        // Going back to the list price removes only that entry.
        try PriceTable.setUserPrice(nil, for: "claude-opus-5-5", at: url)
        let reset = PriceTable.load(user: url, published: nil).table
        XCTAssertEqual(reset.price(for: "claude-opus-5-5"), PriceTable.builtIn.price(for: "claude-opus-5-5"))
        XCTAssertNotNil(reset.price(for: "my-model"))

        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let broken = PriceTable.load(user: url, published: nil)
        XCTAssertNotNil(broken.problem, "a broken file is reported")
        XCTAssertEqual(
            broken.table.price(for: "claude-opus-5-5"),
            PriceTable.builtIn.price(for: "claude-opus-5-5"))
    }

    func testAPublishedListIsKeptOnlyWhenNewerAndSane() throws {
        let url = temporaryURL("published")
        defer { try? FileManager.default.removeItem(at: url) }
        let builtIn = PriceTable.builtIn
        // The test lists are dated 2999, so "now" is set after that.
        let now = try XCTUnwrap(PriceTable.day("2999-06-01"))
        let newer = Data(
            #"{"asOf": "2999-01-01", "models": {"new-model": {"input": 1, "output": 2}, "gpt-6-sol": {"input": 9, "output": 9}}}"#
                .utf8)
        let older = Data(#"{"asOf": "2000-01-01", "models": {"gpt-6-sol": {"input": 1}}}"#.utf8)

        XCTAssertEqual(
            try PriceTable.installPublished(older, at: url, current: builtIn, now: now),
            .alreadyCurrent(builtIn.asOf))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an older list is never written")
        XCTAssertThrowsError(try PriceTable.installPublished(
            Data(#"{"models": {"a": {"input": 1}}}"#.utf8),
            at: url,
            current: builtIn,
            now: now))
        XCTAssertThrowsError(try PriceTable.installPublished(
            Data(#"{"asOf": "2999-01-01", "models": {"a": {"input": -1}}}"#.utf8),
            at: url,
            current: builtIn,
            now: now))
        XCTAssertThrowsError(try PriceTable.installPublished(
            Data("<html>".utf8),
            at: url,
            current: builtIn,
            now: now))

        XCTAssertEqual(
            try PriceTable.installPublished(newer, at: url, current: builtIn, now: now),
            .updated("2999-01-01"))
        let user = temporaryURL("prices")
        defer { try? FileManager.default.removeItem(at: user) }
        try PriceTable.setUserPrice(
            ModelPrice(input: 5, output: 5, cacheRead: 0, cacheWrite: 0),
            for: "gpt-6-sol",
            at: user)

        let table = PriceTable.load(user: user, published: url, now: now).table
        XCTAssertEqual(table.asOf, "2999-01-01")
        XCTAssertTrue(table.usesPublishedList)
        XCTAssertEqual(table.source(for: "new-model"), .published)
        XCTAssertEqual(table.price(for: "gpt-6-sol")?.input, 5, "the reader's price beats the download")
        XCTAssertNotNil(
            table.price(for: "claude-opus-5-5"),
            "models the download leaves out keep their built-in price")
    }

    func testAFutureOrSloppyDateNeverBlocksLaterLists() throws {
        let url = temporaryURL("published")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = try XCTUnwrap(PriceTable.day("2026-11-20"))
        let future = Data(#"{"asOf": "9999-12-31", "models": {"a": {"input": 1}}}"#.utf8)
        XCTAssertThrowsError(try PriceTable.installPublished(future, at: url, current: .builtIn, now: now)) {
            XCTAssertEqual($0 as? PriceList.Problem, .futureDate("9999-12-31"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        for sloppy in ["2026-9-1", "2026-02-31", "2026-11-20T00:00", "２０２６-01-01"] {
            XCTAssertNil(PriceTable.day(sloppy), sloppy)
        }
        XCTAssertNotNil(PriceTable.day("2026-02-28"))

        // A future-dated list already on disk (from an older build) is ignored.
        try future.write(to: url)
        let table = PriceTable.load(user: nil, published: url, now: now).table
        XCTAssertFalse(table.usesPublishedList)
        XCTAssertEqual(table.asOf, PriceTable.builtIn.asOf)
    }

    func testAbsurdTokenCountsSaturateInsteadOfCrashing() {
        let huge = Int.max - 10
        XCTAssertEqual(
            TokenTotals(input: huge, output: huge, cacheRead: huge, cacheWrite: huge).processed,
            .max)
        let usage = [
            ModelUsage(agent: .hermes, model: "model-a", tokens: TokenCount(input: huge)),
            ModelUsage(agent: .opencode, model: "model-a", tokens: TokenCount(input: huge)),
            ModelUsage(agent: .hermes, model: "mystery", tokens: TokenCount(input: huge)),
            ModelUsage(agent: .opencode, model: "mystery", tokens: TokenCount(input: huge))
        ]
        let estimate = table.estimate(usage)
        XCTAssertEqual(estimate.pricedTokens, .max)
        XCTAssertEqual(estimate.unpricedTokens, .max)
        XCTAssertEqual(Int.min.saturatingAdd(-1), .min)
        XCTAssertEqual(2.saturatingAdd(3), 5)
    }

    func testARateTheFileWouldRejectIsNeverSaved() throws {
        let url = temporaryURL("prices")
        defer { try? FileManager.default.removeItem(at: url) }
        try PriceTable.setUserPrice(
            ModelPrice(input: 3, output: 9, cacheRead: 0, cacheWrite: 0), for: "kept", at: url)
        XCTAssertThrowsError(try PriceTable.setUserPrice(
            ModelPrice(input: 1500, output: 1, cacheRead: 0, cacheWrite: 0), for: "typo", at: url))
        {
            XCTAssertEqual($0 as? PriceList.Problem, .badRate("typo"))
        }
        let loaded = PriceTable.load(user: url, published: nil)
        XCTAssertNil(loaded.problem, "the reader's file stays readable")
        XCTAssertEqual(loaded.userPrices["kept"]?.input, 3)
        XCTAssertNil(loaded.userPrices["typo"])
    }

    func testOldPricesAreFlagged() throws {
        let table = PriceTable(asOf: "2026-01-01", prices: [:])
        let day = try XCTUnwrap(PriceTable.day("2026-01-01"))
        XCTAssertFalse(table.isStale(now: day.addingTimeInterval(59 * 86400)))
        XCTAssertTrue(table.isStale(now: day.addingTimeInterval(61 * 86400)))
    }

    /// The repository's `prices.json` is what "Update prices" downloads; it must
    /// never fall behind the list compiled into the release.
    func testThePublishedFileMatchesTheBuiltInList() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let list = try PriceList
            .validatePublished(Data(contentsOf: root.appendingPathComponent("prices.json")))
        XCTAssertEqual(list.asOf, PriceTable.builtIn.asOf)
        XCTAssertEqual(PriceTable(asOf: list.asOf, prices: list.prices).prices, PriceTable.builtIn.prices)
    }

    func testTheBuiltInTableCoversTheCommonAgents() {
        for model in [
            "claude-opus-5-5",
            "claude-sonnet-5-5",
            "gpt-6-luna",
            "gpt-6.1-sol",
            "gemini-3-flash-preview"
        ] {
            XCTAssertNotNil(PriceTable.builtIn.price(for: model), model)
        }
        // Cache reads are always the cheapest kind of input.
        for (model, price) in PriceTable.builtIn.prices {
            XCTAssertLessThanOrEqual(price.cacheRead, price.input, model)
        }
    }
}
