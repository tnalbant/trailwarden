// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

/// The contract every agent parser has to satisfy, checked once and applied to
/// both agents. A new adapter joins by adding a case here.
final class AgentParserCommonTests: XCTestCase {
    private let codexRollout = "rollout-2026-11-14T09-00-00-3f2a1c8e-7b4d-4a11-9c2e-1f0b6d5a8e33.jsonl"

    private func fixture(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(relativePath)")
    }

    private func parsersAndFixtures() -> [(any AgentParser, URL)] {
        [
            (ClaudeCodeParser(), fixture("claude/normal.jsonl")),
            (CodexParser(), fixture("codex/\(codexRollout)")),
        ]
    }

    func testBothAgentsProduceTheSameEventShape() throws {
        for (parser, url) in parsersAndFixtures() {
            let result = try parser.parse(file: url)
            let label = "\(parser.agent.rawValue): "

            XCTAssertFalse(result.events.isEmpty, label + "no events")
            XCTAssertEqual(result.skippedLines, 0, label + "unexpected skipped lines")

            XCTAssertEqual(
                Set(result.events.map(\.id)).count,
                result.events.count,
                label + "duplicate event ids"
            )
            XCTAssertTrue(
                result.events.allSatisfy { $0.agent == parser.agent },
                label + "event attributed to another agent"
            )
            XCTAssertTrue(
                result.events.allSatisfy { !$0.sessionId.isEmpty },
                label + "event without a session id"
            )
            XCTAssertTrue(
                result.events.allSatisfy { ($0.preview?.count ?? 0) <= 500 },
                label + "preview above the cap"
            )
            XCTAssertTrue(
                result.events.allSatisfy { $0.rawJSON != nil },
                label + "event without the source line"
            )
            XCTAssertTrue(
                result.events.allSatisfy { $0.ts.timeIntervalSince1970 > 1_577_836_800 },
                label + "timestamp before 2020 (parse failure)"
            )

            XCTAssertTrue(result.events.contains { $0.kind == .message }, label + "no message event")
            XCTAssertTrue(result.events.contains { $0.kind == .toolCall }, label + "no tool call event")
            XCTAssertTrue(
                result.events.contains { $0.kind == .toolResult && $0.tool != nil },
                label + "tool result without an inherited tool name"
            )
        }
    }

    func testEventIDsDoNotCollideAcrossAgents() throws {
        let claude = try ClaudeCodeParser().parse(file: fixture("claude/normal.jsonl"))
        let codex = try CodexParser().parse(file: fixture("codex/\(codexRollout)"))

        XCTAssertTrue(Set(claude.events.map(\.id)).isDisjoint(with: Set(codex.events.map(\.id))))
    }
}
