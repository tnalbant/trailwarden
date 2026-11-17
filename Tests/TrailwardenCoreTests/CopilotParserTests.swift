// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// The fixture is hand-written in the shape of a real Copilot session
/// (`session-state/<id>/events.jsonl`); every path and value is synthetic.
final class CopilotParserTests: XCTestCase {
    private let sessionID = "5b1e2c3d-0000-4000-8000-00000000c0de"

    private var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/copilot/\(sessionID)/events.jsonl")
    }

    func testSessionMessagesToolsAndTokens() throws {
        let result = try CopilotParser().parse(file: fixture)

        XCTAssertEqual(result.skippedLines, 2, "a broken line and an unknown type; hooks are not counted")
        XCTAssertTrue(result.events.allSatisfy { $0.sessionId == sessionID && $0.agent == .copilot })
        XCTAssertEqual(result.events.first?.kind, .sessionStart)
        XCTAssertEqual(result.events.first?.preview, "copilot 1.0.0")
        XCTAssertTrue(result.events
            .allSatisfy { $0.cwd == "/Users/demo/dev/aurora" && $0.gitBranch == "main" })

        XCTAssertEqual(result.events.filter { $0.kind == .message }.map(\.preview), [
            "make a notes folder and a file in it", "Done."
        ])
        XCTAssertEqual(result.events.filter { $0.kind == .reasoning }.map(\.preview), ["plan the folder"])

        let calls = result.events.filter { $0.kind == .toolCall }
        XCTAssertEqual(calls.map(\.tool), ["bash", "create", "view", "rg"])
        XCTAssertEqual(calls[0].command, "mkdir -p /Users/demo/notes && git push --force origin main")
        XCTAssertNil(calls[1].command, "file content is not a command")
        XCTAssertEqual(calls[1].paths, ["/Users/demo/notes/a.md"])
        XCTAssertFalse(calls[1].preview?.contains("rm -rf") ?? true)
        XCTAssertNil(calls[3].command, "a search pattern is not a command")
        XCTAssertEqual(calls[3].paths, ["/Users/demo/dev/aurora/src"])

        let results = result.events.filter { $0.kind == .toolResult }
        XCTAssertEqual(results.map(\.tool), ["bash", "create", "view"])
        XCTAssertEqual(results[1].paths, ["/Users/demo/notes/a.md"])
        XCTAssertEqual(results[2].preview, "error: denied")

        XCTAssertEqual(
            result.events.filter { $0.kind == .tokenUsage }.map(\.preview),
            ["tokens: 1200 in / 80 out"])
        XCTAssertEqual(result.events.filter { $0.kind == .permission }.map(\.preview), ["shell bash"])
    }

    func testTheRulesSeeCommandsAndFiles() throws {
        let engine = try RuleEngine.builtIn()
        let calls = try CopilotParser().parse(file: fixture).events.filter { $0.kind == .toolCall }
        XCTAssertEqual(calls.map { Set(engine.hits(for: $0).map(\.ruleId)) }, [["R5"], [], ["R11"], []])
    }

    func testIDsAreStableAndOnlyEventsFilesAreRead() throws {
        let first = try CopilotParser().parse(file: fixture).events.map(\.id)
        XCTAssertEqual(first, try CopilotParser().parse(file: fixture).events.map(\.id))
        XCTAssertEqual(Set(first).count, first.count)

        let parser = CopilotParser()
        XCTAssertTrue(parser.accepts(fixture))
        XCTAssertFalse(parser.accepts(URL(fileURLWithPath: "/x/session-state/a/workspace.yaml")))
        XCTAssertFalse(parser.accepts(URL(fileURLWithPath: "/x/session-state/a/other.jsonl")))
    }
}
