// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class FormatCensusTests: XCTestCase {
    private func write(_ lines: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-census-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testCensusCountsKeysNotValues() throws {
        let url = try write([#"{"type":"summary","summary":"secret plan"}"#])
        let census = FormatCensus.census(of: [url], agent: .claudeCode)
        XCTAssertEqual(census["type=summary"], 1)
        XCTAssertEqual(census["key=summary"], 1)
        XCTAssertEqual(census["key=type"], 1)
        XCTAssertFalse(census.keys.contains { $0.contains("secret plan") })
        XCTAssertFalse(FormatCensus.text(census).contains("secret plan"))
    }

    func testCensusAggregatesAcrossLinesAndSkipsBadLines() throws {
        let url = try write([
            #"{"type":"ai-title","aiTitle":"x"}"#,
            "not json",
            #"{"type":"ai-title","aiTitle":"y"}"#,
            #"{"type":"user","message":{}}"#
        ])
        let census = FormatCensus.census(of: [url], agent: .claudeCode)
        XCTAssertEqual(census["type=ai-title"], 2)
        XCTAssertEqual(census["key=aiTitle"], 2)
        XCTAssertEqual(census["type=user"], 1)
        XCTAssertEqual(census["key=message"], 1)
    }

    func testOddNamesAreCountedAsOther() throws {
        let long = String(repeating: "a", count: 41)
        let url = try write([#"{"type":"my secret plan","\#(long)":1}"#])
        let census = FormatCensus.census(of: [url], agent: .claudeCode)
        XCTAssertEqual(census["type=<other>"], 1)
        XCTAssertEqual(census["key=<other>"], 1)
        XCTAssertFalse(FormatCensus.text(census).contains("secret"))
    }
}
