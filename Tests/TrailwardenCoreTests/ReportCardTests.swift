// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class ReportCardTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func call(
        _ id: String,
        _ agent: Agent,
        tool: String,
        session: String,
        cwd: String = "/Users/demo/dev/aurora",
        command: String? = nil,
        paths: [String] = [],
        risk: [RiskHit] = [],
        minutes: Double = 0) -> Event
    {
        Event(
            id: id,
            ts: base.addingTimeInterval(minutes * 60),
            agent: agent,
            sessionId: session,
            kind: .toolCall,
            cwd: cwd,
            tool: tool,
            command: command,
            paths: paths,
            risk: risk)
    }

    private var sample: [Event] {
        [
            call("1", .claudeCode, tool: "Bash", session: "a", command: "swift test"),
            call("2", .claudeCode, tool: "Edit", session: "a", paths: ["/Users/demo/dev/aurora/App.swift"]),
            call("3", .claudeCode, tool: "Edit", session: "a", paths: ["App.swift"]),
            call("4", .codex, tool: "apply_patch", session: "b", paths: ["/Users/demo/dev/aurora/App.swift"]),
            call(
                "5",
                .codex,
                tool: "exec_command",
                session: "b",
                cwd: "/Users/demo/dev/ledger",
                command: "rm -rf ~",
                risk: [RiskHit(ruleId: "R1", severity: .critical, message: "m")],
                minutes: 5),
            call(
                "6",
                .hermes,
                tool: "read_file",
                session: "c",
                paths: ["/Users/demo/.env"],
                risk: [RiskHit(ruleId: "R11", severity: .warn, message: "m")],
                minutes: 9),
            Event(id: "7", ts: base, agent: .hermes, sessionId: "c", kind: .message, preview: "talk")
        ]
    }

    func testCountsWorkByKindAgentAndProject() {
        let card = ReportCard.build(from: sample, since: base, until: base.addingTimeInterval(3600))

        XCTAssertEqual(card.toolCalls, 6, "messages are not tool calls")
        XCTAssertEqual(card.commands, 2)
        XCTAssertEqual(card.edits, 3)
        XCTAssertEqual(card.reads, 1)
        XCTAssertEqual(card.sessions, 3)
        XCTAssertEqual(card.projects, 2)
        XCTAssertEqual(card.critical, 1)
        XCTAssertEqual(card.warnings, 1)
        XCTAssertEqual(card.agents.map(\.agent), [.claudeCode, .codex, .hermes])
        XCTAssertEqual(card.agents.map(\.toolCalls), [3, 2, 1])
    }

    func testHotFilesJoinRelativeAndAbsoluteSpellings() {
        let card = ReportCard.build(from: sample, since: base, until: base)

        XCTAssertEqual(card.filesChanged, 1)
        XCTAssertEqual(card.hotFiles.first?.path, "/Users/demo/dev/aurora/App.swift")
        XCTAssertEqual(card.hotFiles.first?.changes, 3)
        XCTAssertEqual(card.hotFiles.first?.agents, [.claudeCode, .codex])
    }

    func testCriticalFindingsComeFirst() {
        let card = ReportCard.build(from: sample, since: base, until: base)

        XCTAssertEqual(card.worthALook.map(\.id), ["5", "6"])
        XCTAssertEqual(card.rules.map(\.ruleId), ["R1", "R11"])
    }

    func testTheShareableSummaryCarriesNoCommandOrPath() {
        let card = ReportCard.build(from: sample, since: base, until: base.addingTimeInterval(30 * 86400))
        let summary = card.shareableSummary(localizer: Localizer(language: .english))

        XCTAssertTrue(summary.contains("6 tool calls in 3 sessions across 2 projects"), summary)
        XCTAssertTrue(summary.contains("Destructive delete ×1"), summary)
        XCTAssertTrue(summary.contains("Claude Code 3"), summary)
        for secret in ["rm -rf", "aurora", "ledger", ".env", "App.swift", "/Users"] {
            XCTAssertFalse(summary.contains(secret), "summary leaks \(secret)")
        }
    }

    func testEmptyWindow() {
        let card = ReportCard.build(from: [], since: base, until: base)
        XCTAssertTrue(card.isEmpty)
        XCTAssertTrue(card.shareableSummary(localizer: Localizer(language: .turkish))
            .contains("riskli bir şey yok"))
    }
}

final class LiveGuardTests: XCTestCase {
    private func finding(_ id: String, at date: Date, severity: Severity = .critical) -> Event {
        Event(
            id: id, ts: date, agent: .codex, sessionId: "s", kind: .toolCall, tool: "Bash", command: "x",
            risk: [RiskHit(ruleId: "R1", severity: severity, message: "m")])
    }

    func testOnlyNewFindingsAreNewsAndOnlyOnce() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try EventStore(inMemory: true)
        try store.insert(events: [
            finding("old", at: start.addingTimeInterval(-3600)),
            finding("just-before", at: start.addingTimeInterval(-30))
        ])
        var guardState = LiveGuard(threshold: .critical, startedAt: start)

        XCTAssertEqual(
            try guardState.newFindings(in: store).map(\.id),
            ["just-before"],
            "history is not news")

        try store.insert(events: [
            finding("warn", at: start.addingTimeInterval(10), severity: .warn),
            finding("new", at: start.addingTimeInterval(20))
        ])
        XCTAssertEqual(try guardState.newFindings(in: store).map(\.id), ["new"], "below the threshold")
        XCTAssertTrue(try guardState.newFindings(in: store).isEmpty, "a re-read file reports nothing twice")
    }

    func testAlertWordsComeFromTheRule() {
        let event = Event(
            id: "e", ts: Date(), agent: .claudeCode, sessionId: "s", kind: .toolCall,
            cwd: "/Users/demo/dev/aurora", tool: "Bash", command: "rm -rf ~",
            risk: [
                RiskHit(ruleId: "R3", severity: .warn, message: "m"),
                RiskHit(ruleId: "R1", severity: .critical, message: "m")
            ])
        let alert = LiveAlert(event: event, localizer: Localizer(language: .english))

        XCTAssertEqual(alert.title, "Claude Code · Deletes your whole home folder or a system folder")
        XCTAssertEqual(alert.subtitle, "aurora")
        XCTAssertEqual(alert.body, "rm -rf ~")
        XCTAssertEqual(alert.findingKey, "event:e:R1")
        XCTAssertEqual(alert.detailLine, "rm -rf ~  ·  aurora")
    }

    func testLiveAlertLeadsWithTheConsequence() {
        let long = String(repeating: "x", count: 400)
        let event = Event(
            id: "e", ts: Date(), agent: .codex, sessionId: "s", kind: .toolCall,
            cwd: "/Users/demo/dev/aurora", tool: "Bash", command: long,
            risk: [RiskHit(ruleId: "R1", severity: .critical, message: "m")])
        let localizer = Localizer(language: .turkish)
        let alert = LiveAlert(event: event, localizer: localizer)
        let consequence = RuleLocalization.text(forRule: "R1", language: .turkish)?.consequence ?? ""

        XCTAssertFalse(consequence.isEmpty)
        XCTAssertTrue(alert.title.contains(consequence))
        XCTAssertFalse(alert.title.contains("R1"))
        XCTAssertFalse(alert.subtitle.contains("R1"))
        XCTAssertLessThanOrEqual(alert.body.count, 140)
    }

    func testAllowedFindingIsNotNew() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try EventStore(inMemory: true)
        let allowedHit = RiskHit(ruleId: "R1", severity: .critical, message: "m", allowed: true)
        try store.insert(events: [
            Event(
                id: "allowed", ts: start.addingTimeInterval(5), agent: .codex, sessionId: "s",
                kind: .toolCall, tool: "Bash", command: "x", risk: [allowedHit]),
            finding("real", at: start.addingTimeInterval(6))
        ])
        var guardState = LiveGuard(threshold: .critical, startedAt: start)

        XCTAssertEqual(try guardState.newFindings(in: store).map(\.id), ["real"])
    }
}
