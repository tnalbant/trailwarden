// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class TokenUsageTests: XCTestCase {
    func testReadsTheClaudeShape() {
        let totals = TokenTotals(preview: "in 1,234 / out 567")
        XCTAssertEqual(totals?.input, 1234)
        XCTAssertEqual(totals?.output, 567)
        XCTAssertEqual(totals?.processed, 1801)
    }

    func testReadsTheCodexShape() {
        XCTAssertEqual(TokenTotals(preview: "tokens: 20705 in / 90 out")?.processed, 20_795)
        XCTAssertEqual(TokenTotals(preview: "input 12,345 output 678")?.processed, 13_023)
        let context = TokenTotals(preview: "total tokens: 95,336,339")
        XCTAssertEqual(context?.peakContext, 95_336_339)
        XCTAssertEqual(context?.processed, 0, "a running context total is not work done")
    }

    func testIgnoresProseWithoutNumbers() {
        XCTAssertNil(TokenTotals(preview: "no counters here"))
    }

    func testDailyTotalsGroupByDay() throws {
        let store = try EventStore(inMemory: true)
        let now = Date()
        try store.insert(events: [
            Event(id: "t1", ts: now, agent: .codex, sessionId: "s", kind: .tokenUsage,
                  tool: nil, command: nil, paths: [], preview: "tokens: 100 in / 20 out", risk: [], rawJSON: nil),
            Event(id: "t2", ts: now, agent: .codex, sessionId: "s", kind: .tokenUsage,
                  tool: nil, command: nil, paths: [], preview: "total tokens: 9,000", risk: [], rawJSON: nil),
            Event(id: "t3", ts: now.addingTimeInterval(-86_400 * 2), agent: .claudeCode, sessionId: "s2",
                  kind: .tokenUsage, tool: nil, command: nil, paths: [],
                  preview: "in 10 / out 20", risk: [], rawJSON: nil),
        ])

        let daily = try store.dailyTokens(since: now.addingTimeInterval(-86_400 * 7))
        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily.map(\.tokens), [30, 120])

        let byAgent = try store.tokenTotalsByAgent(since: now.addingTimeInterval(-86_400 * 7))
        XCTAssertEqual(byAgent[.codex]?.processed, 120)
        XCTAssertEqual(byAgent[.codex]?.peakContext, 9000)
        XCTAssertEqual(byAgent[.claudeCode]?.input, 10)
    }
}
