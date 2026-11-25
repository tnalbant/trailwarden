// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class ScanVisibilityTests: XCTestCase {
    private func hit(_ rule: String, _ severity: Severity, allowed: Bool = false) -> RiskHit {
        RiskHit(ruleId: rule, severity: severity, message: "m", allowed: allowed)
    }

    private func event(_ id: String, _ risk: [RiskHit]) -> Event {
        Event(
            id: id, ts: Date(timeIntervalSince1970: 1_700_000_000), agent: .claudeCode,
            sessionId: "s", kind: .toolCall, command: "x", risk: risk)
    }

    private var events: [Event] {
        [
            event("a", [hit("R1", .critical), hit("R2", .warn)]),
            event("b", [hit("R3", .warn, allowed: true)]),
            event("c", [hit("R4", .warn), hit("R5", .warn), hit("R6", .warn)])
        ]
    }

    private var states: [String: ReviewState] {
        [
            FindingKey.event("a", rule: "R1"): .reviewed,
            FindingKey.event("c", rule: "R4"): .expected,
            FindingKey.event("c", rule: "R5"): .falsePositive
        ]
    }

    private func rules(_ events: [Event]) -> [String] {
        events.flatMap { $0.risk.map(\.ruleId) }
    }

    func testDefaultHidesAllowedAndReviewed() {
        let shown = ScanVisibility.visible(events, states: states, includeReviewed: false)
        XCTAssertEqual(rules(shown), ["R2", "R6"])
    }

    func testIncludeReviewedShowsEverything() {
        let shown = ScanVisibility.visible(events, states: states, includeReviewed: true)
        XCTAssertEqual(rules(shown), ["R1", "R2", "R3", "R4", "R5", "R6"])
    }

    func testAllowedTotalCountsUnfilteredEvents() {
        XCTAssertEqual(ScanVisibility.allowedTotal(of: events), 1)
    }

    func testGateIgnoresReviewedCriticalWhenOnlyNewWarnRemains() {
        let shown = ScanVisibility.visible(events, states: states, includeReviewed: false)
        XCTAssertFalse(ScanVisibility.gateFails(visibleEvents: shown, threshold: .critical))
        XCTAssertTrue(ScanVisibility.gateFails(visibleEvents: shown, threshold: .warn))
    }
}
