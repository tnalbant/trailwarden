// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class AllowanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEvent(
        id: String = "event-\(UUID().uuidString)",
        command: String,
        cwd: String? = nil) -> Event
    {
        Event(
            id: id,
            ts: now,
            agent: .claudeCode,
            sessionId: "session-1",
            kind: .toolCall,
            cwd: cwd,
            tool: "Bash",
            command: command,
            preview: command)
    }

    private func ruleID(for command: String) throws -> String {
        let engine = try RuleEngine.builtIn()
        return try XCTUnwrap(engine.hits(for: makeEvent(command: command), now: now).first).ruleId
    }

    func testCommandAllowanceMarksTheHitAllowed() throws {
        let command = "rm -rf ~/dist"
        let rule = try ruleID(for: command)
        let engine = try RuleEngine.builtIn(allowances: [
            Allowance(ruleId: rule, scope: .command(command), until: nil, created: now)
        ])

        let hits = engine.hits(for: makeEvent(command: command), now: now)
        XCTAssertEqual(hits.map(\.ruleId), [rule])
        XCTAssertTrue(try XCTUnwrap(hits.first).allowed)

        let other = engine.hits(for: makeEvent(command: "rm -rf ~/src"), now: now)
        XCTAssertEqual(other.map(\.ruleId), [rule])
        XCTAssertFalse(try XCTUnwrap(other.first).allowed)
    }

    func testProjectRuleCoversSubfoldersOnly() {
        let allowance = Allowance(
            ruleId: "R1",
            scope: .projectRule(project: "/Users/demo/app"),
            until: nil,
            created: now)
        XCTAssertTrue(allowance.covers(ruleId: "R1", target: "x", cwd: "/Users/demo/app"))
        XCTAssertTrue(allowance.covers(ruleId: "R1", target: "x", cwd: "/Users/demo/app/web"))
        XCTAssertFalse(allowance.covers(ruleId: "R1", target: "x", cwd: "/Users/demo/application"))
        XCTAssertFalse(allowance.covers(ruleId: "R1", target: "x", cwd: nil))
        XCTAssertFalse(allowance.covers(ruleId: "R2", target: "x", cwd: "/Users/demo/app"))
    }

    func testPatternAllowance() {
        let allowance = Allowance(
            ruleId: "R1",
            scope: .pattern(glob: "rm -rf ./dist*"),
            until: nil,
            created: now)
        XCTAssertTrue(allowance.covers(ruleId: "R1", target: "rm -rf ./dist-old", cwd: nil))
        XCTAssertFalse(allowance.covers(ruleId: "R1", target: "rm -rf ./src", cwd: nil))
    }

    func testEverywhereCoversEveryTargetOfTheRule() {
        let allowance = Allowance(ruleId: "R1", scope: .everywhere, until: nil, created: now)
        XCTAssertTrue(allowance.covers(ruleId: "R1", target: "anything", cwd: nil))
        XCTAssertFalse(allowance.covers(ruleId: "R2", target: "anything", cwd: nil))
    }

    func testExpiredAllowanceDoesNothing() throws {
        let command = "rm -rf ~/dist"
        let rule = try ruleID(for: command)
        let engine = try RuleEngine.builtIn(allowances: [
            Allowance(ruleId: rule, scope: .command(command), until: now.addingTimeInterval(-1), created: now)
        ])
        let hits = engine.hits(for: makeEvent(command: command), now: now)
        XCTAssertEqual(hits.map(\.ruleId), [rule])
        XCTAssertFalse(try XCTUnwrap(hits.first).allowed)
    }

    func testDurations() {
        XCTAssertEqual(AllowanceDuration.oneDay.until(from: now), now.addingTimeInterval(86400))
        XCTAssertEqual(AllowanceDuration.thirtyDays.until(from: now), now.addingTimeInterval(30 * 86400))
        XCTAssertNil(AllowanceDuration.forever.until(from: now))
    }

    func testAllowancesRoundTripThroughTheStore() throws {
        let store = try EventStore(inMemory: true)
        let live = Allowance(
            ruleId: "R1",
            scope: .command("rm -rf ~"),
            until: now.addingTimeInterval(3600),
            created: now)
        let forever = Allowance(
            ruleId: "R2",
            scope: .projectRule(project: "/Users/demo/app"),
            until: nil,
            created: now)
        let pattern = Allowance(ruleId: "R3", scope: .pattern(glob: "x*"), until: nil, created: now)
        let everywhere = Allowance(ruleId: "R4", scope: .everywhere, until: nil, created: now)
        let expired = Allowance(
            ruleId: "R5",
            scope: .command("old"),
            until: now.addingTimeInterval(-60),
            created: now)
        for allowance in [live, forever, pattern, everywhere, expired] {
            try store.addAllowance(allowance)
        }

        XCTAssertEqual(try Set(store.allowances(now: now)), [live, forever, pattern, everywhere])
        XCTAssertEqual(try store.removeExpiredAllowances(now: now), 1)
        try store.removeAllowance(id: forever.id)
        XCTAssertEqual(try Set(store.allowances(now: now)), [live, pattern, everywhere])
    }

    func testAllowedHitsDoNotRaiseSeverity() throws {
        let store = try EventStore(inMemory: true)
        let command = "rm -rf ~"
        let rule = try ruleID(for: command)
        let engine = try RuleEngine.builtIn(allowances: [
            Allowance(ruleId: rule, scope: .command(command), until: nil, created: now)
        ])
        let event = makeEvent(id: "e1", command: command)
        try store.insert(events: engine.annotate([event], now: now))

        let stored = try XCTUnwrap(store.events(ids: ["e1"]).first)
        XCTAssertEqual(stored.risk.count, 1)
        XCTAssertTrue(stored.risk[0].allowed)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(minimumSeverity: .critical)), 0)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(onlyFindings: true)), 0)
        XCTAssertEqual(try store.allowedHitCount(matching: EventQuery()), 1)
        XCTAssertEqual(try store.ruleHitCounts(matching: EventQuery()), [:])
        XCTAssertEqual(try XCTUnwrap(store.sessions().first).criticalCount, 0)
    }

    func testOldRiskJSONStillDecodes() throws {
        let json = #"{"ruleId":"R1","severity":"critical","message":"m"}"#
        let hit = try JSONDecoder().decode(RiskHit.self, from: Data(json.utf8))
        XCTAssertFalse(hit.allowed)
        XCTAssertEqual(hit.ruleId, "R1")
    }

    func testMigratedMuteStillSilences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-allowance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trailwarden.sqlite")

        let command = "rm -rf ~"
        let rule = try ruleID(for: command)
        do {
            let store = try EventStore(url: url)
            for table in ["finding_reviews", "allowances", "file_findings", "archive_copies"] {
                _ = try store.prepareRowStatement("DROP TABLE \(table)").step()
            }
            _ = try store.prepareRowStatement("ALTER TABLE sessions DROP COLUMN title").step()
            _ = try store.prepareRowStatement("ALTER TABLE sessions DROP COLUMN title_source").step()
            _ = try store.prepareRowStatement("ALTER TABLE scanned_files DROP COLUMN missing_since").step()
            let mute = try store.prepareRowStatement(
                "INSERT INTO mutes (rule_id, target, until) VALUES (?,?,?)")
            try mute.bind([
                .text(rule),
                .text(command),
                .double(Date().addingTimeInterval(86400).timeIntervalSince1970)
            ])
            _ = try mute.step()
            _ = try store.prepareRowStatement("PRAGMA user_version = 8").step()
            try store.insert(events: [makeEvent(id: "e1", command: command)])
        }

        let store = try EventStore(url: url)
        try RuleEngine.builtIn(allowances: store.allowances()).reapply(to: store)

        XCTAssertEqual(try store.eventCount(matching: EventQuery(onlyFindings: true)), 0)
        let stored = try XCTUnwrap(store.events(ids: ["e1"]).first)
        XCTAssertTrue(stored.risk.allSatisfy(\.allowed))
        XCTAssertFalse(stored.risk.isEmpty)
    }

    func testAllowedHitDoesNotHideALaterRealFinding() throws {
        let command = "rm -rf ~"
        let rule = try ruleID(for: command)
        let engine = try RuleEngine.builtIn(allowances: [
            Allowance(ruleId: rule, scope: .projectRule(project: "/Users/demo/app"), until: nil, created: now)
        ])
        let inside = makeEvent(command: command, cwd: "/Users/demo/app")
        let outside = makeEvent(command: command, cwd: "/Users/demo/other")

        let annotated = engine.annotate([inside, outside], now: now)

        XCTAssertEqual(annotated[0].risk.map(\.allowed), [true])
        XCTAssertEqual(annotated[1].risk.map(\.allowed), [false])
    }

    func testReAllowingAMigratedMuteKeepsOneRow() throws {
        let store = try EventStore(inMemory: true)
        let insert = try store.prepareRowStatement("""
        INSERT INTO allowances (id, rule_id, scope, value, project, until, created)
        VALUES ('mute:R1|rm -rf ~', 'R1', 'command', 'rm -rf ~', NULL, NULL, 0)
        """)
        _ = try insert.step()

        try store.addAllowance(Allowance(ruleId: "R1", scope: .command("rm -rf ~"), until: nil, created: now))

        XCTAssertEqual(try store.allowances(now: now).count, 1)
    }

    func testProjectPathTrailingSlashStillMatches() {
        let allowance = Allowance(
            ruleId: "R1",
            scope: .projectRule(project: "/Users/demo/app/"),
            until: nil,
            created: now)
        XCTAssertTrue(allowance.covers(ruleId: "R1", target: "x", cwd: "/Users/demo/app"))
        XCTAssertTrue(allowance.covers(ruleId: "R1", target: "x", cwd: "/Users/demo/app/web"))
        XCTAssertFalse(allowance.covers(ruleId: "R1", target: "x", cwd: "/Users/demo/application"))
        XCTAssertEqual(allowance.id, Allowance(
            ruleId: "R1", scope: .projectRule(project: "/Users/demo/app"), until: nil).id)
    }

    func testScopesOfferedForAnEventWithoutCwd() {
        let event = makeEvent(command: "rm -rf   ~/dist")
        let hit = RiskHit(ruleId: "R1", severity: .critical, message: "m")
        let scopes = AllowanceChoice.scopes(for: event, hit: hit)
        XCTAssertEqual(scopes, [.command("rm -rf ~/dist"), .pattern(glob: "rm -rf ~/dist"), .everywhere])
    }

    func testScopesOfferedForAShellEvent() {
        let event = makeEvent(command: "rm -rf ~/dist", cwd: "/Users/demo/app")
        let hit = RiskHit(ruleId: "R1", severity: .critical, message: "m")
        let scopes = AllowanceChoice.scopes(for: event, hit: hit)
        XCTAssertEqual(scopes.count, 4)
        XCTAssertEqual(scopes.first, .command("rm -rf ~/dist"))
        XCTAssertEqual(scopes[1], .projectRule(project: "/Users/demo/app"))
        XCTAssertEqual(scopes[2], .pattern(glob: "rm -rf ~/dist"))
        XCTAssertEqual(scopes[3], .everywhere)
    }

    func testRescopingKeepsEndAndCreationAndChangesTheID() {
        let end = now.addingTimeInterval(86400)
        let original = Allowance(ruleId: "R1", scope: .command("rm -rf ~/dist"), until: end, created: now)
        let moved = original.rescoped(to: .pattern(glob: "rm -rf ~/*"))
        XCTAssertEqual(moved.until, end)
        XCTAssertEqual(moved.created, now)
        XCTAssertEqual(moved.scope, .pattern(glob: "rm -rf ~/*"))
        XCTAssertNotEqual(moved.id, original.id)
        XCTAssertEqual(original.patternPrefill, "rm -rf ~/dist")
        XCTAssertEqual(original.rescoped(to: .projectRule(project: "/a")).patternPrefill, "/a")
    }
}
