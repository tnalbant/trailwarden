// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class EventQueryTests: XCTestCase {
    private var store: EventStore!

    override func setUpWithError() throws {
        store = try EventStore(inMemory: true)
    }

    private func event(
        id: String,
        agent: Agent = .claudeCode,
        secondsFromEpoch: TimeInterval,
        severity: Severity? = nil) -> Event
    {
        Event(
            id: id,
            ts: Date(timeIntervalSince1970: secondsFromEpoch),
            agent: agent,
            sessionId: "s-\(agent.rawValue)",
            kind: .toolCall,
            tool: "Bash",
            command: "cmd \(id)",
            paths: [],
            preview: "cmd \(id)",
            risk: severity.map { [RiskHit(ruleId: "R1", severity: $0, message: "m")] } ?? [],
            rawJSON: nil)
    }

    private func seed() throws {
        try store.insert(events: [
            event(id: "old-critical", secondsFromEpoch: 1000, severity: .critical),
            event(id: "mid-warn", secondsFromEpoch: 2000, severity: .warn),
            event(id: "new-info", secondsFromEpoch: 3000, severity: .info),
            event(id: "newest-clean", secondsFromEpoch: 4000),
            event(id: "codex-warn", agent: .codex, secondsFromEpoch: 3500, severity: .warn)
        ])
    }

    func testSinceFilter() throws {
        try seed()
        let events = try store.events(matching: EventQuery(since: Date(timeIntervalSince1970: 2500)))
        XCTAssertEqual(events.map(\.id), ["newest-clean", "codex-warn", "new-info"])
    }

    func testAgentFilter() throws {
        try seed()
        let events = try store.events(matching: EventQuery(agents: [.codex]))
        XCTAssertEqual(events.map(\.id), ["codex-warn"])
    }

    func testSeverityFilterUsesRankNotAlphabeticalOrder() throws {
        try seed()

        let warnOrWorse = try store.events(matching: EventQuery(minimumSeverity: .warn))
        XCTAssertEqual(Set(warnOrWorse.map(\.id)), ["old-critical", "mid-warn", "codex-warn"])
        XCTAssertFalse(warnOrWorse.contains { $0.id == "new-info" }, "info is below warn")

        let criticalOnly = try store.events(matching: EventQuery(minimumSeverity: .critical))
        XCTAssertEqual(criticalOnly.map(\.id), ["old-critical"])
    }

    func testOnlyFindingsFilter() throws {
        try seed()
        let findings = try store.events(matching: EventQuery(onlyFindings: true))
        XCTAssertEqual(findings.count, 4)
        XCTAssertFalse(findings.contains { $0.id == "newest-clean" })
    }

    func testLimit() throws {
        try seed()
        let events = try store.events(matching: EventQuery(limit: 2))
        XCTAssertEqual(events.map(\.id), ["newest-clean", "codex-warn"])
    }

    func testResultsAreNewestFirst() throws {
        try seed()
        let events = try store.events(matching: EventQuery())
        XCTAssertEqual(events.map(\.ts), events.map(\.ts).sorted(by: >))
    }
}
