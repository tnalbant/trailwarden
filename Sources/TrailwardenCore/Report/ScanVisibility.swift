// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Which hits `scan` prints and which make `--fail-on` exit with 1.
public enum ScanVisibility {
    public static func reviewKeys(of events: [Event]) -> [String] {
        events.flatMap { event in event.risk.map { FindingKey.event(event.id, rule: $0.ruleId) } }
    }

    /// Without `includeReviewed`, a hit that is allowed, or whose finding is
    /// reviewed, expected or a false alarm, is left out.
    public static func visible(
        _ events: [Event],
        states: [String: ReviewState],
        includeReviewed: Bool) -> [Event]
    {
        guard !includeReviewed else { return events }
        return events.map { event in
            event.withRisk(event.risk.filter { hit in
                !hit.allowed && (states[FindingKey.event(event.id, rule: hit.ruleId)] ?? .new) == .new
            })
        }
    }

    public static func allowedTotal(of events: [Event]) -> Int {
        events.reduce(0) { $0 + $1.risk.filter(\.allowed).count }
    }

    /// True when a printed (visible, not allowed) hit reaches the threshold.
    public static func gateFails(visibleEvents: [Event], threshold: Severity) -> Bool {
        visibleEvents.contains { $0.activeRisk.contains { $0.severity >= threshold } }
    }
}
