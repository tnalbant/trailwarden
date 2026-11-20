// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class CodexParserTests: XCTestCase {
    private let parser = CodexParser()
    private let rolloutName = "rollout-2026-11-14T09-00-00-3f2a1c8e-7b4d-4a11-9c2e-1f0b6d5a8e33.jsonl"

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/codex/\(name)")
    }

    // MARK: - Normal session

    func testEventSequenceOfNormalFixture() throws {
        let result = try parser.parse(file: fixture(rolloutName))

        XCTAssertEqual(result.skippedLines, 0)
        XCTAssertEqual(result.events.map(\.kind), [
            .sessionStart,
            .message, .reasoning,
            .toolCall, .toolResult,
            .toolCall, .toolResult,
            .tokenUsage
        ])
    }

    func testSessionIDComesFromTheFileName() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events

        XCTAssertFalse(events.isEmpty)
        for event in events {
            XCTAssertEqual(event.agent, .codex)
            XCTAssertEqual(event.sessionId, "3f2a1c8e-7b4d-4a11-9c2e-1f0b6d5a8e33")
        }
    }

    func testFileNameWithoutUUIDKeepsItsStem() {
        let url = URL(fileURLWithPath: "/tmp/plain-session.jsonl")

        XCTAssertEqual(CodexParser.sessionID(from: url), "plain-session")
        XCTAssertNil(CodexParser.uuidSuffix(of: "plain-session"))
    }

    func testSessionMetaCarriesWorkingDirectory() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events

        let start = try XCTUnwrap(events.first)
        XCTAssertEqual(start.kind, .sessionStart)
        XCTAssertEqual(start.cwd, "/tmp/codex-demo")
        for event in events {
            XCTAssertEqual(event.cwd, "/tmp/codex-demo")
        }
    }

    func testExecToolCallKeepsTheRawCommand() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events
        let call = try XCTUnwrap(events.first { $0.kind == .toolCall })

        XCTAssertEqual(call.tool, "exec")
        XCTAssertEqual(call.command, "ls -la /tmp/codex-demo")
        XCTAssertEqual(call.preview, "ls -la /tmp/codex-demo")
    }

    func testToolOutputsInheritToolNames() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events
        let results = events.filter { $0.kind == .toolResult }

        XCTAssertEqual(results.map(\.tool), ["exec", "js"])
        XCTAssertEqual(results.map(\.preview), ["total 0", "3"])
    }

    func testFunctionCallPreviewComesFromArguments() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events
        let call = events.filter { $0.kind == .toolCall }[1]

        XCTAssertEqual(call.tool, "js")
        XCTAssertEqual(call.preview, "Count files")
        XCTAssertNil(call.command, "a js tool call carries no shell command")
    }

    func testDeveloperMessagesAreSkipped() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events
        let messages = events.filter { $0.kind == .message }

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.preview, "Count the files.")
    }

    func testTokenUsageEvents() throws {
        let events = try parser.parse(file: fixture(rolloutName)).events
        let usage = events.filter { $0.kind == .tokenUsage }

        // The fixture's running total has no input/output split, so only the
        // per-response record counts, normalized and tagged with the turn's model.
        XCTAssertEqual(usage.map(\.preview), ["tokens: 900 in / 80 out (reasoning 10) · demo"])
        XCTAssertEqual(
            usage.first?.usage,
            TokenCount(model: "demo", input: 900, output: 80, reasoning: 10))
    }

    // MARK: - Damaged files

    func testBrokenLinesAreCountedButDoNotStopTheFile() throws {
        let result = try parser.parse(file: fixture("broken.jsonl"))

        XCTAssertEqual(result.events.map(\.kind), [.sessionStart, .message, .toolCall, .toolResult])
        XCTAssertEqual(result.skippedLines, 4, "3 malformed lines + 1 unknown top-level type")
        XCTAssertEqual(result.events.last?.tool, "exec", "the call before the damaged line still resolves")
    }

    func testUnknownTypesAreCountedSeparatelyFromEvents() throws {
        let result = try parser.parse(file: fixture("unknown.jsonl"))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.skippedLines, 2)
        XCTAssertEqual(result.events.first?.preview, "Only real event here.")
    }

    // MARK: - Identity

    func testEventIDsAreUniqueAndStable() throws {
        let first = try parser.parse(file: fixture(rolloutName)).events.map(\.id)
        let second = try parser.parse(file: fixture(rolloutName)).events.map(\.id)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, first.count)
    }
}
