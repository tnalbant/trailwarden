// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

/// The rules a long-running watcher grades with follow the reader's changes,
/// and an allowance is judged at the time of the event it covers.
final class LiveRulesTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-live-rules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The real spelling (/private/var/…), the one a file event reports.
        let real = try XCTUnwrap(realpath(directory.path, nil))
        defer { free(real) }
        directory = URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func toolLine(_ id: String, command: String, at stamp: String) -> String {
        """
        {"type":"assistant","sessionId":"s1","timestamp":"\(stamp)","cwd":"/work/app","message":{"role":"assistant","content":[{"type":"tool_use","id":"\(id)","name":"Bash","input":{"command":"\(command)"}}]}}
        """
    }

    private func event(_ id: String, ts: Date, command: String = "rm -rf ~") -> Event {
        Event(
            id: id,
            ts: ts,
            agent: .claudeCode,
            sessionId: "s1",
            kind: .toolCall,
            cwd: "/work/app",
            tool: "Bash",
            command: command,
            preview: command)
    }

    private func ruleID(for command: String) throws -> String {
        try XCTUnwrap(RuleEngine.builtIn().evaluateCommand(command).first).ruleId
    }

    // MARK: - C1: the live path picks up allowances and rule changes

    func testAllowedFindingStaysAllowedWhenTheTranscriptGrows() throws {
        let store = try EventStore(url: directory.appendingPathComponent("index.sqlite"))
        let transcripts = directory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        let file = transcripts.appendingPathComponent("s1.jsonl")
        try (toolLine("toolu_1", command: "rm -rf ~", at: "2026-11-14T08:00:00.000Z") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        let roots = [ScanRoot(directory: transcripts, parser: ClaudeCodeParser())]
        let rules = CurrentRules { try RuleCatalog.builtIn() }

        // The live guard's catch-up scan.
        _ = try TranscriptScanner(store: store, rules: rules.engine(for: store)).scan(roots: roots)
        XCTAssertEqual(try store.eventCount(matching: EventQuery(onlyFindings: true)), 1)

        // The app allows the finding and re-grades the index.
        let rule = try ruleID(for: "rm -rf ~")
        try store.addAllowance(Allowance(ruleId: rule, scope: .projectRule(project: "/work/app"), until: nil))
        try store.reapplyCurrentRules { try RuleCatalog.builtIn() }
        XCTAssertEqual(try store.eventCount(matching: EventQuery(onlyFindings: true)), 0)
        let allowedHits = try store.allowedHitCount(matching: EventQuery())
        XCTAssertGreaterThan(allowedHits, 0)

        // The agent writes again; the live pass re-reads the whole file.
        let grown = toolLine("toolu_1", command: "rm -rf ~", at: "2026-11-14T08:00:00.000Z") + "\n"
            + toolLine("toolu_2", command: "ls", at: "2026-11-14T08:01:00.000Z") + "\n"
        try grown.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        _ = try TranscriptScanner(store: store, rules: rules.engine(for: store))
            .scan(changed: [file], roots: roots, databases: [])

        XCTAssertEqual(try store.eventCount(matching: EventQuery(onlyFindings: true)), 0, "still allowed")
        XCTAssertEqual(try store.allowedHitCount(matching: EventQuery()), allowedHits)
    }

    func testEngineIsRebuiltOnlyWhenTheGenerationMoves() throws {
        let store = try EventStore(inMemory: true)
        var reads = 0
        let rules = CurrentRules {
            reads += 1
            return try RuleCatalog.builtIn()
        }
        _ = try rules.engine(for: store)
        _ = try rules.engine(for: store)
        XCTAssertEqual(reads, 1, "an unchanged generation reuses the engine")

        try store.addAllowance(Allowance(ruleId: "R1", scope: .everywhere, until: nil))
        let afterAllow = try rules.engine(for: store)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(afterAllow.allowances.map(\.ruleId), ["R1"])

        try store.removeAllowance(id: afterAllow.allowances[0].id)
        XCTAssertTrue(try rules.engine(for: store).allowances.isEmpty)

        try store.bumpRulesGeneration()
        _ = try rules.engine(for: store)
        XCTAssertEqual(reads, 4, "a rule change (bump) is read again too")
    }

    func testDisabledRuleStopsFiringOnTheLivePath() throws {
        let store = try EventStore(inMemory: true)
        let rule = try ruleID(for: "rm -rf ~")
        var disabled = false
        let rules = CurrentRules {
            try RuleCatalog.builtIn().map { $0.id == rule && disabled ? $0.with(
                enabled: false,
                severity: $0.severity) : $0 }
        }
        XCTAssertFalse(try rules.engine(for: store).hits(for: event("e1", ts: now)).isEmpty)

        disabled = true
        try store.bumpRulesGeneration()
        XCTAssertFalse(try rules.engine(for: store).hits(for: event("e1", ts: now))
            .contains { $0.ruleId == rule })
    }

    // MARK: - I1: coverage is judged at the event's time

    func testExpiredAllowanceStillCoversEarlierEvents() throws {
        let store = try EventStore(inMemory: true)
        let rule = try ruleID(for: "rm -rf ~")
        let until = now
        try store.addAllowance(Allowance(
            ruleId: rule, scope: .command("rm -rf ~"), until: until, created: now.addingTimeInterval(-86400)))
        let before = event("before", ts: until.addingTimeInterval(-3600))
        let after = event("after", ts: until.addingTimeInterval(3600))
        try store.insert(events: [before, after])

        // Re-graded two days after the allowance ran out.
        let engine = try RuleEngine.grading(store, rules: RuleCatalog.builtIn())
        try engine.reapply(to: store)

        let stored = try Dictionary(uniqueKeysWithValues: store.events(ids: ["before", "after"]).map { (
            $0.id,
            $0) })
        XCTAssertEqual(stored["before"]?.risk.map(\.allowed), [true], "allowed before the end")
        XCTAssertEqual(stored["after"]?.risk.map(\.allowed), [false], "not covered after the end")
        XCTAssertTrue(
            try store.allowances(now: now.addingTimeInterval(2 * 86400)).isEmpty,
            "expired for display")
    }

    func testNewAllowanceCoversEventsFromBeforeIt() throws {
        let rule = try ruleID(for: "rm -rf ~")
        let engine = try RuleEngine.builtIn(allowances: [
            Allowance(
                ruleId: rule,
                scope: .command("rm -rf ~"),
                until: now.addingTimeInterval(86400),
                created: now)
        ])
        XCTAssertEqual(
            engine.hits(for: event("old", ts: now.addingTimeInterval(-30 * 86400))).map(\.allowed),
            [true])
    }

    // MARK: - I5: a change during a re-grade gets its own pass

    func testAllowanceStoredDuringAReapplyIsApplied() throws {
        let store = try EventStore(inMemory: true)
        let rule = try ruleID(for: "rm -rf ~")
        try store.insert(events: [event("e1", ts: now)])
        var passes = 0
        try store.reapplyCurrentRules {
            passes += 1
            if passes == 1 {
                // The reader allows the finding while the first pass is running.
                try store.addAllowance(Allowance(ruleId: rule, scope: .everywhere, until: nil))
            }
            return try RuleCatalog.builtIn()
        }
        XCTAssertEqual(passes, 2)
        XCTAssertEqual(try store.events(ids: ["e1"]).first?.risk.map(\.allowed), [true])
    }

    func testGenerationCounts() throws {
        let store = try EventStore(inMemory: true)
        XCTAssertEqual(try store.rulesGeneration(), 0)
        try store.bumpRulesGeneration()
        try store.bumpRulesGeneration()
        XCTAssertEqual(try store.rulesGeneration(), 2)
    }
}
