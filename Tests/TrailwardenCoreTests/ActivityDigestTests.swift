// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
@testable import TrailwardenCore
import XCTest

final class ActivityDigestTests: XCTestCase {
    private func event(
        id: String = "e1",
        kind: EventKind = .toolCall,
        tool: String? = "terminal",
        command: String? = nil,
        paths: [String] = [],
        preview: String? = nil,
        cwd: String? = "/Users/demo/work/trailwarden",
        minutesAgo: Double = 0,
        risk: [RiskHit] = [])
        -> Event
    {
        Event(
            id: id,
            ts: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60),
            agent: .claudeCode,
            sessionId: "s1",
            kind: kind,
            cwd: cwd,
            tool: tool,
            command: command,
            paths: paths,
            preview: preview,
            risk: risk)
    }

    func testBookkeepingKindsAreDropped() {
        let events = [
            event(id: "a", kind: .tokenUsage),
            event(id: "b", kind: .sessionStart),
            event(id: "c", kind: .permission),
            event(id: "d", kind: .toolCall, command: "ls")
        ]
        XCTAssertEqual(ActivityDigest.items(from: events).map(\.id), ["d"])
    }

    func testNewestFirst() {
        let events = [
            event(id: "old", minutesAgo: 30),
            event(id: "new", minutesAgo: 1),
            event(id: "mid", minutesAgo: 10)
        ]
        XCTAssertEqual(ActivityDigest.items(from: events).map(\.id), ["new", "mid", "old"])
    }

    func testCommandBecomesTheDetail() {
        let item = ActivityDigest.item(from: event(command: "swift test"))
        XCTAssertEqual(item.label, "terminal")
        XCTAssertEqual(item.detail, "swift test")
    }

    func testFirstPathStandsInForCommands() {
        let item = ActivityDigest.item(from: event(
            tool: "patch",
            paths: ["/Users/demo/work/trailwarden/Sources/A.swift",
                    "/Users/demo/work/trailwarden/Sources/B.swift"]))
        XCTAssertEqual(item.label, "patch")
        XCTAssertTrue(item.detail.hasPrefix("~/work/trailwarden/Sources/A.swift"))
        XCTAssertTrue(item.detail.hasSuffix("(+1)"))
    }

    func testMultilineCommandsAreFlattenedAndCut() {
        let long = String(repeating: "x", count: 140)
        let item = ActivityDigest.item(from: event(command: "cd /tmp\n   echo \"\(long)\""))
        XCTAssertFalse(item.detail.contains("\n"))
        XCTAssertTrue(item.detail.contains("⏎"))
        XCTAssertLessThanOrEqual(item.detail.count, ActivityDigest.detailLimit + 1)
        XCTAssertTrue(item.detail.hasSuffix("…"))
    }

    func testProjectIsTheFolderName() {
        XCTAssertEqual(ActivityDigest.project(from: "/Users/demo/work/trailwarden"), "trailwarden")
        XCTAssertEqual(ActivityDigest.project(from: "/Users/demo"), "~")
        XCTAssertNil(ActivityDigest.project(from: nil))
        XCTAssertNil(ActivityDigest.project(from: ""))
    }

    func testWorstRuleHitIsCarried() {
        let risk = [
            RiskHit(ruleId: "R1", severity: .warn, message: "warn"),
            RiskHit(ruleId: "R4", severity: .critical, message: "credential file")
        ]
        let item = ActivityDigest.item(from: event(command: "cat .env", risk: risk))
        XCTAssertEqual(item.severity, .critical)
        XCTAssertEqual(item.ruleMessage, "credential file")
    }

    func testLimitKeepsTheNewest() {
        let events = (0 ..< 10).map { event(id: "e\($0)", minutesAgo: Double($0)) }
        let items = ActivityDigest.items(from: events, limit: 3)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first?.id, "e0")
    }

    func testWiderDetailLimitShowsMoreOfTheCommand() {
        let long = String(repeating: "y", count: 200)
        let narrow = ActivityDigest.item(from: event(command: long))
        let wide = ActivityDigest.item(from: event(command: long), detailLimit: 200)
        XCTAssertLessThan(narrow.detail.count, wide.detail.count)
        XCTAssertLessThanOrEqual(wide.detail.count, 201)
    }

    func testMessageRowsAreMarkedAsSuch() {
        let item = ActivityDigest.item(from: event(
            kind: .message, tool: nil, preview: "şu dosyaya bak"))
        XCTAssertTrue(item.isMessage)
        XCTAssertEqual(item.label, "message")
        XCTAssertEqual(item.detail, "şu dosyaya bak")
    }

    /// The stored message is the rules file's own text; a row has to follow the
    /// interface language or an English window shows a Turkish sentence.
    func testTheRuleLineFollowsTheInterfaceLanguage() {
        let item = ActivityDigest.item(from: event(
            command: "rm -rf ~/old",
            risk: [RiskHit(ruleId: "R1", severity: .critical, message: "stored text")]))

        XCTAssertEqual(item.ruleId, "R1")
        let english = item.ruleLine(Localizer(language: .english))
        let turkish = item.ruleLine(Localizer(language: .turkish))
        XCTAssertEqual(english, RuleLocalization.text(forRule: "R1", language: .english)?.message)
        XCTAssertEqual(turkish, RuleLocalization.text(forRule: "R1", language: .turkish)?.message)
        XCTAssertNotEqual(english, turkish, "the two languages cannot render the same line")
    }

    func testAnUnknownRuleFallsBackToTheStoredMessage() {
        let item = ActivityDigest.item(from: event(
            command: "hand written rule",
            risk: [RiskHit(ruleId: "R999", severity: .warn, message: "stored text")]))
        XCTAssertNil(RuleLocalization.text(forRule: "R999", language: .english))
        XCTAssertEqual(item.ruleLine(Localizer(language: .english)), "stored text")
    }

    func testARowWithoutARuleHasNoRuleLine() {
        let item = ActivityDigest.item(from: event(command: "ls"))
        XCTAssertNil(item.ruleLine(Localizer(language: .english)))
    }
}
