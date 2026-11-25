// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class ReviewStateTests: XCTestCase {
    private var directory: URL!
    private var store: EventStore!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try EventStore(inMemory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func event(id: String, ts: Date, command: String = "rm -rf /", risk: [RiskHit]) -> Event {
        Event(
            id: id,
            ts: ts,
            agent: .claudeCode,
            sessionId: "session-1",
            kind: .toolCall,
            tool: "Bash",
            command: command,
            preview: command,
            risk: risk)
    }

    private func hit(_ rule: String, allowed: Bool = false) -> RiskHit {
        RiskHit(ruleId: rule, severity: .warn, message: "m", allowed: allowed)
    }

    private func reviewRowCount() throws -> Int {
        let statement = try store.prepareRowStatement("SELECT COUNT(*) FROM finding_reviews")
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }

    func testReviewRoundTrip() throws {
        try store.setReview(.expected, for: "event:e1:R1", at: now)
        XCTAssertEqual(try store.reviewStates(for: ["event:e1:R1"]), ["event:e1:R1": .expected])

        try store.setReview(.new, for: "event:e1:R1", at: now)
        XCTAssertEqual(try store.reviewStates(for: ["event:e1:R1", "event:e2:R1"]), [
            "event:e1:R1": .new,
            "event:e2:R1": .new
        ])
        XCTAssertEqual(try reviewRowCount(), 0, "new deletes the row")
    }

    func testReviewSurvivesRescan() throws {
        let line = """
        {"type":"assistant","sessionId":"s1","timestamp":"2026-11-14T08:00:02.000Z","cwd":"/tmp/demo","gitBranch":"main","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"rm -rf /","description":"wipe"}}]}}
        """
        let file = directory.appendingPathComponent("a.jsonl")
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)
        let scanner = try TranscriptScanner(
            store: store,
            redactor: Redactor(level: .normal),
            rules: RuleEngine.builtIn())
        let roots = [ScanRoot(directory: directory, parser: ClaudeCodeParser())]

        _ = try scanner.scan(roots: roots)
        let found = try XCTUnwrap(store.events(matching: EventQuery()).first { !$0.risk.isEmpty })
        let key = try FindingKey.event(found.id, rule: XCTUnwrap(found.risk.first).ruleId)
        try store.setReview(.reviewed, for: key, at: now)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: file.path)
        let second = try scanner.scan(roots: roots)
        XCTAssertEqual(second.filesParsed, 1, "the touched file is parsed again")

        let again = try XCTUnwrap(store.events(matching: EventQuery()).first { !$0.risk.isEmpty })
        XCTAssertEqual(again.id, found.id, "the event id is stable across a rescan")
        XCTAssertEqual(try store.reviewStates(for: [key]), [key: .reviewed])
    }

    func testReviewSurvivesCatalogueReapply() throws {
        try store.insert(events: [event(id: "e1", ts: now, risk: [])])
        let engine = try RuleEngine.builtIn()
        try engine.reapply(to: store)
        let rule = try XCTUnwrap(store.events(ids: ["e1"]).first?.risk.first).ruleId
        let key = FindingKey.event("e1", rule: rule)
        try store.setReview(.reviewed, for: key, at: now)

        try engine.reapply(to: store)

        XCTAssertEqual(try store.reviewStates(for: [key]), [key: .reviewed])
    }

    func testMarkAllReviewedLeavesNewerOnes() throws {
        try store.insert(events: [
            event(id: "old", ts: now.addingTimeInterval(-7200), risk: [hit("R1")]),
            event(id: "new", ts: now.addingTimeInterval(3600), risk: [hit("R1")]),
            event(id: "allowed", ts: now.addingTimeInterval(-7200), risk: [hit("R2", allowed: true)])
        ])

        let changed = try store.markAllReviewed(foundBefore: now, at: now)

        XCTAssertEqual(changed, 1)
        let states = try store.reviewStates(for: [
            FindingKey.event("old", rule: "R1"),
            FindingKey.event("new", rule: "R1"),
            FindingKey.event("allowed", rule: "R2")
        ])
        XCTAssertEqual(states[FindingKey.event("old", rule: "R1")], .reviewed)
        XCTAssertEqual(states[FindingKey.event("new", rule: "R1")], .new)
        XCTAssertEqual(states[FindingKey.event("allowed", rule: "R2")], .new)
    }

    func testMarkAllReviewedCoversFileFindingsAndKeepsExistingStates() throws {
        let kept = FindingKey.event("old", rule: "R1")
        try store.insert(events: [event(id: "old", ts: now.addingTimeInterval(-60), risk: [hit("R1")])])
        try store.setReview(.falsePositive, for: kept, at: now)
        let fileKey = FindingKey.file(path: "~/a.env", rule: "R9", digest: "abc")
        let insert = try store.prepareRowStatement("""
        INSERT INTO file_findings (finding_key, path, rule_id, severity, line, preview, found_at)
        VALUES (?,?,?,?,?,?,?)
        """)
        try insert.bind([
            .text(fileKey), .text("~/a.env"), .text("R9"), .text("warn"), .int(1), .text("p"),
            .double(now.addingTimeInterval(-30).timeIntervalSince1970)
        ])
        try insert.step()

        XCTAssertEqual(try store.markAllReviewed(foundBefore: now, at: now), 1)

        let states = try store.reviewStates(for: [kept, fileKey])
        XCTAssertEqual(states[kept], .falsePositive)
        XCTAssertEqual(states[fileKey], .reviewed)
    }

    func testPruneDropsOrphanReviews() throws {
        try store.insert(events: [
            event(id: "old", ts: now.addingTimeInterval(-200 * 86400), risk: [hit("R1")]),
            event(id: "kept", ts: now, risk: [hit("R1")])
        ])
        try store.setReview(.reviewed, for: FindingKey.event("old", rule: "R1"), at: now)
        try store.setReview(.reviewed, for: FindingKey.event("kept", rule: "R1"), at: now)

        try store.prune(eventsOlderThanDays: 90, now: now)

        let states = try store.reviewStates(for: [
            FindingKey.event("old", rule: "R1"),
            FindingKey.event("kept", rule: "R1")
        ])
        XCTAssertEqual(states[FindingKey.event("old", rule: "R1")], .new)
        XCTAssertEqual(states[FindingKey.event("kept", rule: "R1")], .reviewed)
        XCTAssertEqual(try reviewRowCount(), 1)
    }

    func testFalsePositiveCounts() throws {
        try store.setReview(.falsePositive, for: "event:e1:R4", at: now)
        try store.setReview(.falsePositive, for: "event:e2:R4", at: now)
        try store.setReview(.falsePositive, for: "event:e3:R12", at: now)
        try store.setReview(.expected, for: "event:e4:R4", at: now)

        XCTAssertEqual(try store.falsePositiveCounts(), ["R4": 2, "R12": 1])
    }
}
