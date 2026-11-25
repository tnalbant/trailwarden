// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class InboxTests: XCTestCase {
    private var store: EventStore!
    private let launch = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        store = try EventStore(inMemory: true)
    }

    private func event(_ id: String, ago: TimeInterval, risk: [RiskHit]) -> Event {
        Event(
            id: id,
            ts: launch.addingTimeInterval(-ago),
            agent: .claudeCode,
            sessionId: "s1",
            kind: .toolCall,
            cwd: "/work/app",
            tool: "Bash",
            command: "run \(id)",
            preview: "run \(id)",
            risk: risk)
    }

    private func hit(_ rule: String, _ severity: Severity, allowed: Bool = false) -> RiskHit {
        RiskHit(ruleId: rule, severity: severity, message: "m", allowed: allowed)
    }

    func testInboxOrdersWorstFirst() throws {
        try store.insert(events: [
            event("warn-new", ago: 10, risk: [hit("R1", .warn)]),
            event("crit-old", ago: 500, risk: [hit("R2", .critical)]),
            event("crit-new", ago: 100, risk: [hit("R2", .critical)]),
            event("info", ago: 1, risk: [hit("R3", .info)])
        ])
        let snapshot = try Inbox.load(from: store, now: launch)
        XCTAssertEqual(snapshot.unreviewed.map(\.id), [
            "event:crit-new:R2", "event:crit-old:R2", "event:warn-new:R1", "event:info:R3"
        ])
    }

    func testReviewedAndAllowedStayOut() throws {
        try store.insert(events: [
            event("e1", ago: 10, risk: [hit("R1", .warn)]),
            event("e2", ago: 20, risk: [hit("R1", .warn, allowed: true)]),
            event("e3", ago: 30, risk: [hit("R1", .warn), hit("R2", .critical, allowed: true)])
        ])
        try store.setReview(.reviewed, for: "event:e1:R1", at: launch)
        let snapshot = try Inbox.load(from: store, now: launch)
        XCTAssertEqual(snapshot.unreviewed.map(\.id), ["event:e3:R1"])
    }

    func testUnreviewedCriticalCount() throws {
        try store.insert(events: [
            event("e1", ago: 10, risk: [hit("R1", .critical)]),
            event("e2", ago: 20, risk: [hit("R1", .critical)]),
            event("e3", ago: 30, risk: [hit("R2", .warn)])
        ])
        try store.setReview(.falsePositive, for: "event:e2:R1", at: launch)
        let snapshot = try Inbox.load(from: store, now: launch, limit: 1)
        XCTAssertEqual(snapshot.unreviewedCritical, 1)
        XCTAssertEqual(snapshot.unreviewed.count, 1)
    }

    private func seedBacklog() throws {
        try store.insert(events: [
            event("o1", ago: 300, risk: [hit("R1", .critical)]),
            event("o2", ago: 200, risk: [hit("R1", .warn)]),
            event("o3", ago: 100, risk: [hit("R2", .warn)])
        ])
    }

    func testBacklogChoiceAppearsOnceAndClears() throws {
        try seedBacklog()
        XCTAssertEqual(try Inbox.load(from: store, now: launch).backlog, 3)
        // Still pending on the next look.
        XCTAssertEqual(try Inbox.load(from: store, now: launch.addingTimeInterval(60)).backlog, 3)

        try Inbox.resolveBacklog(store, markReviewed: true, now: launch.addingTimeInterval(120))
        let cleared = try Inbox.load(from: store, now: launch.addingTimeInterval(180))
        XCTAssertNil(cleared.backlog)
        XCTAssertEqual(cleared.unreviewedCritical, 0)
        XCTAssertTrue(cleared.unreviewed.isEmpty)

        try store.insert(events: [
            Event(
                id: "fresh",
                ts: launch.addingTimeInterval(200),
                agent: .codex,
                sessionId: "s2",
                kind: .toolCall,
                command: "x",
                risk: [hit("R1", .critical)])
        ])
        let later = try Inbox.load(from: store, now: launch.addingTimeInterval(300))
        XCTAssertEqual(later.unreviewed.map(\.id), ["event:fresh:R1"])
        XCTAssertNil(later.backlog)
        XCTAssertEqual(later.unreviewedCritical, 1)
    }

    func testShowInInboxKeepsThem() throws {
        try seedBacklog()
        XCTAssertEqual(try Inbox.load(from: store, now: launch).backlog, 3)
        try Inbox.resolveBacklog(store, markReviewed: false, now: launch)
        let snapshot = try Inbox.load(from: store, now: launch)
        XCTAssertNil(snapshot.backlog)
        XCTAssertEqual(snapshot.unreviewed.count, 3)
    }

    func testFileFindingsJoinTheInbox() throws {
        let key = FindingKey.file(path: "~/a.env", rule: "R9", digest: "abc")
        try store.database.execute("""
        INSERT INTO file_findings (finding_key, path, rule_id, severity, line, preview, found_at)
        VALUES ('\(key)', '~/a.env', 'R9', 'critical', 3, 'KEY=***', \(launch.timeIntervalSince1970))
        """)
        let snapshot = try Inbox.load(from: store, now: launch)
        XCTAssertEqual(snapshot.unreviewed.map(\.id), [key])
        XCTAssertEqual(snapshot.unreviewedCritical, 1)
    }

    func testCountOnlyPathAgreesWithLoad() throws {
        try store.insert(events: [
            event("c1", ago: 10, risk: [hit("R1", .critical), hit("R2", .critical)]),
            event("c2", ago: 20, risk: [hit("R1", .critical)]),
            event("c3", ago: 30, risk: [hit("R1", .critical, allowed: true), hit("R3", .warn)]),
            event("w1", ago: 40, risk: [hit("R3", .warn)])
        ])
        try store.database.execute("""
        INSERT INTO file_findings (finding_key, path, rule_id, severity, line, preview, found_at)
        VALUES ('file:~/a:R9:abc', '~/a', 'R9', 'critical', 1, 'x', \(launch.timeIntervalSince1970))
        """)
        try store.setReview(.reviewed, for: "event:c2:R1", at: launch)
        let loaded = try Inbox.load(from: store, now: launch).unreviewedCritical
        XCTAssertEqual(loaded, 3)
        XCTAssertEqual(try Inbox.unreviewedCriticalCount(in: store), loaded)
    }

    func testEqualSeverityAndTimeSortById() throws {
        try store.insert(events: [
            event("b", ago: 10, risk: [hit("R1", .warn)]),
            event("a", ago: 10, risk: [hit("R1", .warn)]),
            event("c", ago: 10, risk: [hit("R1", .warn)])
        ])
        let snapshot = try Inbox.load(from: store, now: launch)
        XCTAssertEqual(snapshot.unreviewed.map(\.id), ["event:a:R1", "event:b:R1", "event:c:R1"])
    }

    func testPartlyReviewedEventKeepsItsOpenHit() throws {
        try store.insert(events: [
            event("e1", ago: 10, risk: [hit("R1", .critical), hit("R2", .warn)]),
            event("e2", ago: 20, risk: [hit("R1", .warn)])
        ])
        try store.setReview(.reviewed, for: "event:e1:R1", at: launch)
        try store.setReview(.falsePositive, for: "event:e2:R1", at: launch)
        XCTAssertEqual(
            try store.eventsWithUnreviewedFindings().map(\.id),
            ["e1"],
            "fully reviewed events are skipped")
        let snapshot = try Inbox.load(from: store, now: launch)
        XCTAssertEqual(snapshot.unreviewed.map(\.id), ["event:e1:R2"])
        XCTAssertEqual(snapshot.unreviewedCritical, 0)
        XCTAssertEqual(try Inbox.unreviewedCriticalCount(in: store), 0)
    }
}
