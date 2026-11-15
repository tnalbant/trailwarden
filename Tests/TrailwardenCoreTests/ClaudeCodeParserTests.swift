// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class ClaudeCodeParserTests: XCTestCase {
    private let parser = ClaudeCodeParser()

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/\(name)")
    }

    // MARK: - Normal session

    func testEventSequenceOfNormalFixture() throws {
        let result = try parser.parse(file: fixture("normal.jsonl"))

        XCTAssertEqual(result.skippedLines, 0)
        XCTAssertEqual(result.events.map(\.kind), [
            .message, .reasoning, .message,
            .toolCall, .toolResult,
            .toolCall, .toolResult,
            .permission, .permission,
            .message
        ])
    }

    func testSessionContextIsCarriedOnEveryEvent() throws {
        let result = try parser.parse(file: fixture("normal.jsonl"))

        XCTAssertFalse(result.events.isEmpty)
        for event in result.events {
            XCTAssertEqual(event.agent, .claudeCode)
            XCTAssertEqual(event.sessionId, "sess-0001")
            XCTAssertEqual(event.cwd, "/tmp/demo")
            XCTAssertEqual(event.gitBranch, "main")
            XCTAssertTrue(event.risk.isEmpty, "rules are applied later, not by the parser")
            XCTAssertNotNil(event.rawJSON)
        }
    }

    func testShellToolCallCarriesCommandAndDescription() throws {
        let events = try parser.parse(file: fixture("normal.jsonl")).events
        let bash = try XCTUnwrap(events.first { $0.kind == .toolCall })

        XCTAssertEqual(bash.tool, "Bash")
        XCTAssertEqual(bash.command, "ls -la")
        XCTAssertEqual(bash.preview, "List files")
        XCTAssertEqual(bash.paths, [])
    }

    func testFileToolCallCarriesPath() throws {
        let events = try parser.parse(file: fixture("normal.jsonl")).events
        let calls = events.filter { $0.kind == .toolCall }

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].tool, "Read")
        XCTAssertEqual(calls[1].paths, ["/tmp/demo/notes.md"])
    }

    func testToolResultInheritsToolNameFromItsCall() throws {
        let events = try parser.parse(file: fixture("normal.jsonl")).events
        let results = events.filter { $0.kind == .toolResult }

        XCTAssertEqual(results.map(\.tool), ["Bash", "Read"])
        XCTAssertEqual(results[0].preview, "total 8\ndrwxr-xr-x  notes.md")
        XCTAssertEqual(results[1].preview, "hello")
        XCTAssertEqual(results[1].paths, ["/tmp/demo/notes.md"])
    }

    func testPermissionLinesBecomePermissionEvents() throws {
        let events = try parser.parse(file: fixture("normal.jsonl")).events
        let permissions = events.filter { $0.kind == .permission }

        XCTAssertEqual(permissions.map(\.preview), [
            "permission mode: acceptEdits",
            "mode: default"
        ])
        // These lines carry no timestamp of their own: the last known one is used.
        let reference = try XCTUnwrap(events.last { $0.kind == .toolResult }?.ts)
        XCTAssertEqual(permissions[0].ts, reference)
        XCTAssertEqual(permissions[1].ts, reference)
    }

    func testPreviewIsCappedAtFiveHundredCharacters() throws {
        let events = try parser.parse(file: fixture("normal.jsonl")).events
        let long = try XCTUnwrap(events.last)

        XCTAssertEqual(long.kind, .message)
        // Absolute expectation on purpose: comparing against
        // ClaudeCodeParser.previewLimit would make the test follow the constant
        // and stop catching a changed cap.
        XCTAssertEqual(long.preview?.count, 500)
        XCTAssertEqual(long.preview, String(repeating: "a", count: 500))
    }

    // MARK: - Damaged files

    func testBrokenLinesAreCountedButDoNotStopTheFile() throws {
        let result = try parser.parse(file: fixture("broken.jsonl"))

        XCTAssertEqual(result.events.count, 4)
        XCTAssertEqual(result.skippedLines, 4, "3 malformed lines + 1 unknown type")
        XCTAssertEqual(result.events.map(\.kind), [.message, .message, .toolCall, .toolResult])
        XCTAssertEqual(result.events.last?.sessionId, "sess-broken")
        XCTAssertEqual(result.events.last?.tool, "Bash", "the call before the damaged line still resolves")
    }

    func testUnknownTypesAreCountedSeparatelyFromEvents() throws {
        let result = try parser.parse(file: fixture("unknown.jsonl"))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.skippedLines, 2)
        XCTAssertEqual(result.events.first?.preview, "Only real event here.")
    }

    // MARK: - Identity

    func testEventIDsAreUniqueAndStable() throws {
        let first = try parser.parse(file: fixture("normal.jsonl")).events.map(\.id)
        let second = try parser.parse(file: fixture("normal.jsonl")).events.map(\.id)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, first.count)
    }

    func testMissingFileThrows() {
        let missing = fixture("does-not-exist.jsonl")

        XCTAssertThrowsError(try parser.parse(file: missing))
    }
}
