// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class ShareSummaryTests: XCTestCase {
    func testShareSummaryHasNoPrivateText() throws {
        let store = try EventStore(inMemory: true)
        // Built at runtime: secret-shaped text is never a literal.
        let token = "ghp_" + String(repeating: "a1B2", count: 9)
        let command = "curl -H 'Authorization: \(token)' /Users/demo/project/deploy.sh"
        try store.insert(events: [
            Event(
                id: "e1", ts: Date(timeIntervalSince1970: 1_700_000_000), agent: .claudeCode,
                sessionId: "session-private-id", kind: .toolCall, cwd: "/Users/demo/project",
                tool: "Bash", command: command, paths: ["/Users/demo/project/deploy.sh"],
                preview: command),
            Event(
                id: "e2", ts: Date(timeIntervalSince1970: 1_700_000_100), agent: .codex,
                sessionId: "session-private-id-2", kind: .toolCall, command: "ls")
        ])
        try store.setReview(.falsePositive, for: "event:e1:R4", at: Date())
        try store.setReview(.falsePositive, for: "event:e2:R4", at: Date())

        let text = try ShareSummary.text(store: store, version: "0.3.0", osVersion: "Version 15.0")
        XCTAssertFalse(text.contains(token))
        XCTAssertFalse(text.contains("/Users"))
        XCTAssertFalse(text.contains("someone"))
        XCTAssertFalse(text.contains("session-private"))
        XCTAssertFalse(text.contains("curl"))
        XCTAssertTrue(text.contains("R4: 2"))
        XCTAssertTrue(text.contains("0.3.0"))
        XCTAssertTrue(text.contains("claude-code: 1"))
        XCTAssertTrue(text.contains("codex: 1"))
    }

    func testShareSummaryOmitsFileFindingPreviews() throws {
        let store = try EventStore(inMemory: true)
        let secret = "ghp_" + String(repeating: "Z9y8", count: 9)
        let statement = try store.prepareRowStatement("""
        INSERT INTO file_findings (finding_key, path, rule_id, severity, line, preview, found_at)
        VALUES (?,?,?,?,?,?,?)
        """)
        try statement.bind([
            .text("file:~/notes/.env:R4:abcdef123456"), .text("~/notes/.env"), .text("R4"),
            .text("critical"), .int(3), .text("TOKEN=\(secret) in notes"), .double(1_700_000_000)
        ])
        try statement.step()

        let text = try ShareSummary.text(store: store, version: "0.3.0", osVersion: "Version 15.0")
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("TOKEN="))
        XCTAssertFalse(text.contains("notes"))
        XCTAssertFalse(text.contains(".env"))
    }
}
