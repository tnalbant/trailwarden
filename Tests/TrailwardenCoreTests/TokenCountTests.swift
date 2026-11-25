// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

/// Token counts are the base of any cost estimate, so each agent's shape is
/// pinned here: which numbers include the cache, and which lines repeat.
final class TokenCountTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-tokens-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ lines: [String], name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Normalizing

    func testOpenAIShapeSplitsTheCacheOutOfTheInput() {
        let count = TokenCount.includingCache(
            model: "m", input: 1000, cached: 700, cacheWrite: 200, output: 50, reasoning: 20)
        XCTAssertEqual(
            count,
            TokenCount(model: "m", input: 100, output: 50, cacheRead: 700, cacheWrite: 200, reasoning: 20))
        XCTAssertEqual(count.processed, 1050, "nothing counted twice")
        // A cache larger than the input (a broken line) never goes negative.
        XCTAssertEqual(
            TokenCount.includingCache(model: nil, input: 10, cached: 50, output: 0, reasoning: 0).input,
            0)
    }

    func testRunningTotalsBecomeDifferences() {
        let first = TokenCount(input: 100, output: 10, cacheRead: 50)
        let second = TokenCount(model: "m", input: 160, output: 25, cacheRead: 90)
        XCTAssertEqual(second.since(first), TokenCount(model: "m", input: 60, output: 15, cacheRead: 40))
        XCTAssertTrue(second.since(second).isEmpty)
    }

    func testNumbersFromJSON() {
        XCTAssertEqual(TokenCount.number(12), 12)
        XCTAssertEqual(TokenCount.number(12.0), 12)
        XCTAssertEqual(TokenCount.number("12"), 12)
        XCTAssertEqual(TokenCount.number(-5), 0)
        XCTAssertEqual(TokenCount.number(Double.infinity), Int.max)
        XCTAssertEqual(TokenCount.number(nil), 0)
    }

    // MARK: - Claude Code

    func testClaudeCodeCountsEachResponseOnce() throws {
        /// One response is written as one line per content block, each carrying
        /// the same usage. A second response follows; a synthetic line has none.
        func line(_ request: String, _ block: String, output: Int, model: String = "claude-test") -> String {
            #"{"type":"assistant","sessionId":"s1","requestId":"\#(request)","timestamp":"2026-11-14T09:00:00.000Z","# +
                #""cwd":"/tmp/demo","message":{"id":"msg-\#(request)","model":"\#(model)","content":[{"type":"text","text":"\#(block)"}],"# +
                #""usage":{"input_tokens":3,"output_tokens":\#(output),"cache_read_input_tokens":4000,"# +
                #""cache_creation_input_tokens":500,"output_tokens_details":{"thinking_tokens":7}}}}"#
        }
        let file = try write([
            line("r1", "a", output: 20),
            line("r1", "b", output: 20),
            line("r2", "c", output: 30),
            #"{"type":"assistant","sessionId":"s1","message":{"model":"<synthetic>","content":[],"usage":{"input_tokens":0,"output_tokens":0}}}"#
        ], name: "s1.jsonl")

        let tokens = try ClaudeCodeParser().parse(file: file).events.filter { $0.kind == .tokenUsage }
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(
            tokens.first?.usage,
            TokenCount(
                model: "claude-test",
                input: 3,
                output: 20,
                cacheRead: 4000,
                cacheWrite: 500,
                reasoning: 7))
        XCTAssertEqual(tokens.first?.cwd, "/tmp/demo")
        XCTAssertEqual(Set(tokens.map(\.id)).count, 2)
    }

    // MARK: - Codex

    func testCodexCountsTheChangeInTheRunningTotal() throws {
        func total(_ input: Int, _ cached: Int, _ output: Int) -> String {
            #"{"timestamp":"2026-11-14T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"# +
                #""total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"# +
                #""output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}}}}"#
        }
        let file = try write([
            #"{"timestamp":"2026-11-14T09:00:00.000Z","type":"turn_context","payload":{"model":"gpt-test"}}"#,
            total(1000, 800, 50),
            total(1000, 800, 50), // Codex reports the same turn twice
            total(1600, 1300, 90),
            #"{"timestamp":"2026-11-14T09:00:00.000Z","type":"token_usage_record","payload":{"usage":{"input_tokens":9,"output_tokens":9}}}"#
        ], name: "rollout-2026-11-14T09-00-00-0f0e0d0c-0b0a-4908-8706-050403020100.jsonl")

        let tokens = try CodexParser().parse(file: file).events.compactMap(\.usage)
        XCTAssertEqual(tokens, [
            TokenCount(model: "gpt-test", input: 200, output: 50, cacheRead: 800),
            TokenCount(model: "gpt-test", input: 100, output: 40, cacheRead: 500)
        ], "the repeat adds nothing and the per-response record is not counted on top")
    }

    // MARK: - Gemini and Copilot

    func testGeminiThoughtsAreBilledAsOutput() {
        let usage = GeminiCLIParser.usage([
            "model": "gemini-test",
            "tokens": ["input": 13206, "output": 25, "cached": 11367, "thoughts": 44, "total": 13275]
        ])
        XCTAssertEqual(
            usage,
            TokenCount(model: "gemini-test", input: 1839, output: 69, cacheRead: 11367, reasoning: 44))
        XCTAssertEqual(usage?.processed, 13275, "the same total Gemini reports")
    }

    func testCopilotInputIncludesBothCaches() {
        let count = CopilotParser.count([
            "model": "gpt-test", "inputTokens": 38569, "outputTokens": 318,
            "cacheReadTokens": 38110, "cacheWriteTokens": 456, "reasoningTokens": 201
        ])
        XCTAssertEqual(
            count,
            TokenCount(
                model: "gpt-test",
                input: 3,
                output: 318,
                cacheRead: 38110,
                cacheWrite: 456,
                reasoning: 201))
    }

    // MARK: - Store

    private func tokenEvent(_ id: String, _ usage: TokenCount?, agent: Agent = .claudeCode) -> Event {
        Event(
            id: id,
            ts: Date(),
            agent: agent,
            sessionId: "s-\(id)",
            kind: .tokenUsage,
            preview: usage?.preview ?? "tokens: 10 in / 5 out",
            usage: usage)
    }

    func testTheStoreKeepsTheSplitAndTheModel() throws {
        let store = try EventStore(inMemory: true)
        let usage = TokenCount(
            model: "claude-test",
            input: 3,
            output: 20,
            cacheRead: 4000,
            cacheWrite: 500,
            reasoning: 7)
        _ = try store.insert(events: [tokenEvent("a", usage), tokenEvent("b", usage), tokenEvent("c", nil)])

        XCTAssertEqual(try store.event(id: "a")?.usage, usage)
        XCTAssertNil(try store.event(id: "c")?.usage)

        let since = Date().addingTimeInterval(-3600)
        let byAgent = try store.tokenTotalsByAgent(since: since)
        XCTAssertEqual(byAgent[.claudeCode]?.cacheRead, 8000)
        XCTAssertEqual(
            byAgent[.claudeCode]?.processed,
            2 * usage.processed + 15,
            "the old preview row still counts")

        let byModel = try store.tokenCountsByModel(since: since)
        XCTAssertEqual(byModel.count, 1)
        XCTAssertEqual(byModel.first?.model, "claude-test")
        XCTAssertEqual(byModel.first?.tokens.output, 40)
    }

    func testUpgradingDropsOldTokenRowsAndRereadsDatabasesOnce() throws {
        let url = directory.appendingPathComponent("index.sqlite")
        do {
            let store = try EventStore(url: url)
            try store.markReread(agent: .hermes)
            var old = tokenEvent("old", nil, agent: .hermes)
            old = Event(
                id: old.id,
                ts: old.ts,
                agent: .hermes,
                sessionId: "h1",
                kind: .tokenUsage,
                preview: old.preview)
            let call = Event(
                id: "call",
                ts: Date(),
                agent: .hermes,
                sessionId: "h1",
                kind: .toolCall,
                command: "ls")
            _ = try store.insert(events: [old, call])
            XCTAssertNotNil(try store.latestTimestamp(agent: .hermes))
            // Pretend this file was written by the release before token columns.
            let downgrade = try store.prepareRowStatement("PRAGMA user_version = 6")
            _ = try downgrade.step()
        }

        let store = try EventStore(url: url)
        XCTAssertNil(try store.event(id: "old"), "a preview-only token row is dropped")
        XCTAssertNotNil(try store.event(id: "call"), "everything else stays")
        XCTAssertNil(try store.latestTimestamp(agent: .hermes), "the database is read in full once")
        try store.markReread(agent: .hermes)
        XCTAssertNotNil(try store.latestTimestamp(agent: .hermes))
    }
}
