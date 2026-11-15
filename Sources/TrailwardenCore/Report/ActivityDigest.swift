// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// One line of "what the agent actually did".
///
/// The panel and the day feed both answer that question, so the shape lives in
/// Core where it can be tested without a window: a tool in the agent's own
/// vocabulary, the thing it touched, and the rule hit if there was one.
public struct ActivityItem: Sendable, Identifiable, Equatable {
    public let id: String
    public let time: Date
    public let agent: Agent
    public let sessionID: String
    /// "terminal", "patch", "read_file" — the tool name the agent used.
    public let label: String
    /// The command, the first path, or the message text, flattened to one line.
    public let detail: String
    public let project: String?
    public let severity: Severity?
    public let ruleMessage: String?
    public let kind: EventKind

    public var isMessage: Bool {
        kind == .message
    }
}

public enum ActivityDigest {
    /// A row shows this much of a command; the rest is one click away.
    static let detailLimit = 90

    /// Newest first, without the rows that are bookkeeping rather than activity:
    /// token counters, session markers and permission prompts say nothing about
    /// what the agent did.
    public static func items(from events: [Event], limit: Int = 40) -> [ActivityItem] {
        events
            .filter { event in
                switch event.kind {
                case .tokenUsage, .sessionStart, .permission: false
                default: true
                }
            }
            .sorted { $0.ts > $1.ts }
            .prefix(limit)
            .map(item(from:))
    }

    public static func item(from event: Event) -> ActivityItem {
        let hit = event.risk.max { $0.severity < $1.severity }
        return ActivityItem(
            id: event.id,
            time: event.ts,
            agent: event.agent,
            sessionID: event.sessionId,
            label: label(for: event),
            detail: detail(for: event) ?? "",
            project: project(from: event.cwd),
            severity: hit?.severity,
            ruleMessage: hit?.message,
            kind: event.kind)
    }

    static func label(for event: Event) -> String {
        switch event.kind {
        case .message: "message"
        case .reasoning: "thinking"
        case .fileChange: "file change"
        case .toolResult: event.tool ?? "result"
        default: event.tool ?? event.kind.rawValue
        }
    }

    static func detail(for event: Event) -> String? {
        let raw: String?
        if let command = event.command, !command.isEmpty {
            raw = command
        } else if let path = event.paths.first {
            let extra = event.paths.count > 1 ? " (+\(event.paths.count - 1))" : ""
            raw = Redactor().shortenHome(path) + extra
        } else {
            raw = event.preview
        }
        guard let raw, !raw.isEmpty else { return nil }
        return collapse(raw)
    }

    /// Transcripts are full of newlines and runs of spaces. One line reads better
    /// in a row, and the untouched text is in the detail view.
    static func collapse(_ text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard flattened.count > detailLimit else { return flattened }
        return String(flattened.prefix(detailLimit)) + "…"
    }

    /// The folder name a person would recognise, or nil when the agent recorded
    /// nothing (a chat-only session).
    public static func project(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let shortened = Redactor().shortenHome(cwd)
        return shortened.split(separator: "/").last.map(String.init) ?? shortened
    }
}
