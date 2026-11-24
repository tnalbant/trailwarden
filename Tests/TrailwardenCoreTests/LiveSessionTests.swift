// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class LiveSessionTests: XCTestCase {
    private func event(_ id: String, mine: Int, session: String) -> Event {
        Event(
            id: id,
            ts: Date().addingTimeInterval(-Double(mine) * 60),
            agent: .codex,
            sessionId: session,
            kind: .toolCall,
            tool: "Bash",
            command: "ls",
            paths: [],
            preview: "ls",
            risk: [],
            rawJSON: nil)
    }

    func testOnlyRecentSessionsCount() throws {
        let store = try EventStore(inMemory: true)
        try store.insert(events: [
            event("a", mine: 0, session: "now"),
            event("b", mine: 1, session: "now"),
            event("c", mine: 30, session: "half-hour"),
            event("d", mine: 300, session: "old")
        ])

        XCTAssertEqual(try store.activeSessionIDs(within: 120), ["now"])
        XCTAssertEqual(try store.activeSessionIDs(within: 3600), ["now", "half-hour"])
    }

    func testEmptyStoreHasNoLiveSessions() throws {
        let store = try EventStore(inMemory: true)
        XCTAssertTrue(try store.activeSessionIDs().isEmpty)
    }

    func testLiveAlertTitleUsesTheRuleTitle() throws {
        let localizer = Localizer(language: .english)
        let hit = RiskHit(ruleId: "R1", severity: .critical, message: "stored message")
        let event = Event(
            id: "alert",
            ts: Date(),
            agent: .claudeCode,
            sessionId: "s",
            kind: .toolCall,
            tool: "Bash",
            command: "ls",
            paths: [],
            preview: "ls",
            risk: [hit],
            rawJSON: nil)
        let title = try XCTUnwrap(RuleLocalization.text(forRule: "R1", language: .english)).title
        let alert = LiveAlert(event: event, localizer: localizer)
        XCTAssertEqual(alert.title, "Claude Code · \(title)")
        XCTAssertFalse(alert.title.contains("R1"))
    }
}
