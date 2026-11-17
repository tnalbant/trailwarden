// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

public extension Agent {
    /// How the agent is named in a sentence or a notification.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .opencode: "opencode"
        case .gemini: "Gemini CLI"
        case .hermes: "Hermes"
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        }
    }
}

/// Decides which findings are news. The watcher re-reads a transcript every
/// time the agent appends to it, so the same finding comes back on every pass;
/// and the first pass after launch would otherwise report the whole history.
///
/// A finding is news once: when it happened after the guard started (with a
/// short grace for the write that woke the watcher) and it has not been
/// reported before.
public struct LiveGuard: Sendable {
    public let threshold: Severity
    public let startedAt: Date
    /// Transcripts are flushed a little after the command runs; a finding stamped
    /// shortly before the guard started is still live.
    public let grace: TimeInterval
    public private(set) var reported: Set<String> = []

    public init(threshold: Severity = .critical, startedAt: Date = Date(), grace: TimeInterval = 120) {
        self.threshold = threshold
        self.startedAt = startedAt
        self.grace = grace
    }

    /// New findings, oldest first, each reported once.
    public mutating func newFindings(in store: EventStore) throws -> [Event] {
        var query = EventQuery(since: startedAt.addingTimeInterval(-grace), minimumSeverity: threshold)
        query.includeRawJSON = false
        query.limit = 200
        let fresh = try store.events(matching: query)
            .filter { !reported.contains($0.id) }
            .sorted { $0.ts < $1.ts }
        for event in fresh {
            reported.insert(event.id)
        }
        return fresh
    }
}

/// The words of one live notification, so the app and `trailwarden watch` say
/// the same thing.
public struct LiveAlert: Sendable, Equatable {
    public let title: String
    public let subtitle: String
    public let body: String

    public init(event: Event, localizer: Localizer) {
        let worst = event.risk.max { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.ruleId > rhs.ruleId : lhs.severity < rhs.severity
        }
        let rule = worst.flatMap { hit in
            RuleLocalization.text(forRule: hit.ruleId, language: localizer.language)
        }
        title = "\(event.agent.displayName) · \(rule?.title ?? worst?.ruleId ?? "")"
        subtitle = rule?.message ?? worst?.message ?? ""
        var what = event.command ?? event.paths.first ?? event.preview ?? ""
        what = what.replacingOccurrences(of: "\n", with: " ⏎ ")
        if what.count > 140 {
            what = String(what.prefix(139)) + "…"
        }
        if let project = ActivityDigest.project(from: event.cwd) {
            body = "\(what)\n\(project)"
        } else {
            body = what
        }
    }
}
