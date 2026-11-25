// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class RuleRefreshTests: XCTestCase {
    private var store: EventStore!

    override func setUpWithError() throws {
        store = try EventStore(inMemory: true)
    }

    private func event(id: String, command: String, seconds: TimeInterval = 1000) -> Event {
        Event(
            id: id,
            ts: Date(timeIntervalSince1970: seconds),
            agent: .claudeCode,
            sessionId: "s1",
            kind: .toolCall,
            cwd: "/Users/demo/dev/demo",
            tool: "Bash",
            command: command,
            paths: [],
            preview: command,
            risk: [],
            rawJSON: nil)
    }

    private func rules(disabling id: String? = nil, severity: Severity? = nil) throws -> [Rule] {
        try RuleCatalog.builtIn().map { rule in
            guard rule.id == id else { return rule }
            return rule.with(enabled: severity != nil, severity: severity ?? rule.severity)
        }
    }

    func testReapplyWritesHitsForRawEvents() throws {
        try store.insert(events: [event(id: "e1", command: "rm -rf /")])
        XCTAssertTrue(try XCTUnwrap(store.events(ids: ["e1"]).first).risk.isEmpty)

        let report = try RuleEngine.builtIn().reapply(to: store)

        XCTAssertEqual(report.events, 1)
        XCTAssertEqual(report.changed, 1)
        let event = try XCTUnwrap(store.events(ids: ["e1"]).first)
        XCTAssertEqual(event.risk.map(\.ruleId), ["R1"])
        XCTAssertEqual(event.risk.first?.severity, .critical)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(minimumSeverity: .critical)), 1)
    }

    func testReapplyIsIdempotent() throws {
        try store.insert(events: [event(id: "e1", command: "rm -rf /")])
        try RuleEngine.builtIn().reapply(to: store)

        let second = try RuleEngine.builtIn().reapply(to: store)

        XCTAssertEqual(second.events, 1)
        XCTAssertEqual(second.changed, 0, "nothing changed, so nothing is rewritten")
    }

    func testDisablingARuleClearsStoredHitsAndSessionCount() throws {
        try store.insert(events: [event(id: "e1", command: "rm -rf /")])
        try RuleEngine.builtIn().reapply(to: store)
        XCTAssertEqual(try XCTUnwrap(store.sessions().first).criticalCount, 1)

        let engine = try RuleEngine(rules: rules(disabling: "R1"))
        let report = try engine.reapply(to: store)

        XCTAssertEqual(report.changed, 1)
        let event = try XCTUnwrap(store.events(ids: ["e1"]).first)
        XCTAssertTrue(event.risk.isEmpty)
        XCTAssertEqual(try XCTUnwrap(store.sessions().first).criticalCount, 0)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(minimumSeverity: .warn)), 0)
    }

    func testChangingSeverityRewritesTheRank() throws {
        try store.insert(events: [event(id: "e1", command: "sudo ls")])
        try RuleEngine.builtIn().reapply(to: store)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(minimumSeverity: .critical)), 0)

        let engine = try RuleEngine(rules: rules(disabling: "R3", severity: .critical))
        try engine.reapply(to: store)

        let event = try XCTUnwrap(store.events(ids: ["e1"]).first)
        XCTAssertEqual(event.risk.first { $0.ruleId == "R3" }?.severity, .critical)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(minimumSeverity: .critical)), 1)
        XCTAssertEqual(try XCTUnwrap(store.sessions().first).criticalCount, 1)
    }

    func testAllowanceMarksTheHitOnReapply() throws {
        let muted = event(id: "e1", command: "rm -rf /")
        try store.insert(events: [muted])
        try RuleEngine.builtIn().reapply(to: store)

        let target = RuleEngine.target(for: muted)
        let allowance = Allowance(
            ruleId: "R1",
            scope: .command(target),
            until: Date().addingTimeInterval(30 * 86400))
        try store.addAllowance(allowance)

        let engine = try RuleEngine(rules: RuleCatalog.builtIn(), allowances: store.allowances())
        try engine.reapply(to: store)

        XCTAssertEqual(target, "rm -rf /")
        let hits = try XCTUnwrap(store.events(ids: ["e1"]).first).risk
        XCTAssertEqual(hits.map(\.ruleId), ["R1"])
        XCTAssertTrue(hits.allSatisfy(\.allowed))
        XCTAssertEqual(try store.eventCount(matching: EventQuery(onlyFindings: true)), 0)
        XCTAssertEqual(try store.allowances().count, 1, "the allowance survives the rewrite")
    }

    func testRawTextIsNotLoadedDuringReevaluation() throws {
        let event = Event(
            id: "e1", ts: Date(timeIntervalSince1970: 1000), agent: .codex, sessionId: "s1",
            kind: .toolCall, tool: "exec", command: "sudo ls", risk: [],
            rawJSON: String(repeating: "x", count: 4096))
        try store.insert(events: [event])

        let loaded = try XCTUnwrap(store.eventsForReevaluation().first)

        XCTAssertNil(loaded.rawJSON, "raw lines are not needed to re-run the rules")
        XCTAssertEqual(loaded.command, "sudo ls")
    }
}
