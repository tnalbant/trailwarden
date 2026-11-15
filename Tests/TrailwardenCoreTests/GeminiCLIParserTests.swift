// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class GeminiCLIParserTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gemini/session-2026-06-02T17-32-test.json")
    }

    func testParsesShellCallAndProse() throws {
        let result = try GeminiCLIParser().parse(file: fixtureURL)

        XCTAssertEqual(result.skippedLines, 0)
        XCTAssertEqual(result.events.count, 4, "user turn, shell call, read call, closing prose")

        let shell = try XCTUnwrap(result.events.first { $0.command == "brew upgrade gemini-cli" })
        XCTAssertEqual(shell.agent, .gemini)
        XCTAssertEqual(shell.tool, "Bash", "run_shell_command is normalised to the canonical tool name")
        XCTAssertEqual(shell.kind, .toolCall)
        XCTAssertEqual(shell.sessionId, "bec37c68-test-session")

        let read = try XCTUnwrap(result.events.first { $0.tool == "Read" })
        XCTAssertEqual(read.paths, ["/Users/demo/demo/README.md"])
        XCTAssertEqual(read.preview, "/Users/demo/demo/README.md")

        let user = try XCTUnwrap(result.events
            .first { $0.kind == .message && $0.preview == "brew upgrade gemini-cli" })
        XCTAssertNotNil(user.ts.timeIntervalSince1970 > 0)
    }

    func testInfoMessagesAreNotEvents() throws {
        let result = try GeminiCLIParser().parse(file: fixtureURL)
        XCTAssertFalse(result.events.contains { $0.preview?.contains("update available") == true })
    }

    func testForeignJSONIsIgnoredNotFailed() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notes.json")
        try #"{"hello": "world"}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try GeminiCLIParser().parse(file: url)
        XCTAssertTrue(result.events.isEmpty, "a JSON file that is not a transcript yields nothing")
    }

    func testUnreadableTranscriptThrows() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("session-broken.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertThrowsError(try GeminiCLIParser().parse(file: url))
    }

    func testCanonicalToolNamesUnifyAgents() {
        XCTAssertEqual(RuleEngine.canonicalTool("run_shell_command"), "Bash")
        XCTAssertEqual(RuleEngine.canonicalTool("exec"), "Bash")
        XCTAssertEqual(RuleEngine.canonicalTool("Bash"), "Bash")
        XCTAssertEqual(RuleEngine.canonicalTool("read_file"), "Read")
        XCTAssertEqual(RuleEngine.canonicalTool("apply_patch"), "Write")
        XCTAssertEqual(RuleEngine.canonicalTool("something-new"), "something-new")
        XCTAssertNil(RuleEngine.canonicalTool(nil))
    }

    func testBashRuleMatchesGeminiShellCall() throws {
        let rules = [Rule(
            id: "T1", title: "shell", severity: .warn,
            match: RuleMatch(tool: "Bash", commandRegex: "brew\\s+upgrade"),
            message: "package upgrade")]
        let engine = try RuleEngine(rules: rules)
        let event = Event(
            id: "e1", ts: Date(), agent: .gemini, sessionId: "s", kind: .toolCall,
            tool: "Bash", command: "brew upgrade gemini-cli", risk: [], rawJSON: nil)

        XCTAssertEqual(engine.hits(for: event).map(\.ruleId), ["T1"])
    }
}
