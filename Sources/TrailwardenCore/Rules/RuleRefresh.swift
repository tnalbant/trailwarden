// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

public struct RuleRefreshReport: Sendable, Equatable {
    public let events: Int
    public let changed: Int
    public let duration: TimeInterval

    public init(events: Int, changed: Int, duration: TimeInterval) {
        self.events = events
        self.changed = changed
        self.duration = duration
    }
}

public extension RuleEngine {
    /// Re-runs the rules over the stored index and writes back the events whose
    /// hits changed. Turning a rule off, re-grading it or allowing a situation only
    /// takes effect in the timeline once this has run.
    @discardableResult
    func reapply(to store: EventStore, now: Date = Date()) throws -> RuleRefreshReport {
        let started = Date()
        let events = try store.eventsForReevaluation()
        var changed: [String: [RiskHit]] = [:]

        for event in events {
            let hits = hits(for: event, now: now)
            if !Self.sameHits(hits, event.risk) {
                changed[event.id] = hits
            }
        }

        try store.replaceRisk(changed)
        return RuleRefreshReport(
            events: events.count,
            changed: changed.count,
            duration: Date().timeIntervalSince(started))
    }

    /// Order-insensitive comparison of two hit lists.
    static func sameHits(_ lhs: [RiskHit], _ rhs: [RiskHit]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let left = lhs.map { "\($0.ruleId)|\($0.severity.rawValue)|\($0.allowed)" }.sorted()
        let right = rhs.map { "\($0.ruleId)|\($0.severity.rawValue)|\($0.allowed)" }.sorted()
        return left == right
    }
}
