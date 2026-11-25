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
    /// The rule's own id, so the line can be rendered in the reader's language.
    public let ruleId: String?
    /// The message stored with the event — the rules file's text, not the
    /// reader's language. `ruleLine(_:)` is what a view should show.
    public let ruleMessage: String?
    public let kind: EventKind
    /// What the action was, in the one verb the interface uses.
    public let verb: ActionVerb
    /// What it touched (a project-relative path, a command, the words said),
    /// without the verb. `summary(_:)` is what a row should show.
    public let object: String
    /// The path in `object` is not inside the session's project.
    public let outsideProject: Bool

    public var isMessage: Bool {
        kind == .message
    }

    /// One plain line, "Ran npm test", in the interface language.
    public func summary(_ localizer: Localizer) -> String {
        EventPresentation.summary(verb: verb, object: object, localizer: localizer)
    }

    /// The rule's short title in the interface language, or its id when unknown.
    public func ruleTitle(_ localizer: Localizer) -> String? {
        guard let ruleId else { return nil }
        return RuleLocalization.text(forRule: ruleId, language: localizer.language)?.title ?? ruleId
    }

    /// The rule line in the interface language, falling back to the stored
    /// message when the id is unknown (a rule added by hand, or an old event).
    public func ruleLine(_ localizer: Localizer) -> String? {
        if let ruleId, let text = RuleLocalization.text(forRule: ruleId, language: localizer.language) {
            return text.message
        }
        return ruleMessage
    }
}

public enum ActivityDigest {
    /// A row shows this much of a command; the rest is one click away.
    public static let detailLimit = 90

    /// Newest first, without the rows that are bookkeeping rather than activity:
    /// token counters, session markers and permission prompts say nothing about
    /// what the agent did.
    public static func items(
        from events: [Event],
        limit: Int = 40,
        detailLimit: Int = ActivityDigest.detailLimit)
        -> [ActivityItem]
    {
        events
            .filter { event in
                switch event.kind {
                case .tokenUsage, .sessionStart, .permission: false
                default: true
                }
            }
            .sorted { $0.ts > $1.ts }
            .prefix(limit)
            .map { item(from: $0, detailLimit: detailLimit) }
    }

    public static func item(
        from event: Event,
        detailLimit: Int = ActivityDigest.detailLimit) -> ActivityItem
    {
        let hit = event.activeRisk.max { $0.severity < $1.severity }
        return ActivityItem(
            id: event.id,
            time: event.ts,
            agent: event.agent,
            sessionID: event.sessionId,
            label: label(for: event),
            detail: detail(for: event, limit: detailLimit) ?? "",
            project: project(from: event.cwd),
            severity: hit?.severity,
            ruleId: hit?.ruleId,
            ruleMessage: hit?.message,
            kind: event.kind,
            verb: EventPresentation.verb(for: event),
            object: EventPresentation.object(for: event),
            outsideProject: EventPresentation.touchesOutsideProject(event))
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

    static func detail(for event: Event, limit: Int = ActivityDigest.detailLimit) -> String? {
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
        return collapse(raw, limit: limit)
    }

    /// Transcripts are full of newlines and runs of spaces. One line reads better
    /// in a row, and the untouched text is in the detail view.
    static func collapse(_ text: String, limit: Int = ActivityDigest.detailLimit) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }

    /// Always "15 Nov 21:00", never a bare "21:00". A row that shows only a time
    /// cannot say which day it belongs to, and the reader should not have to
    /// infer it from a scroll position.
    public static func stamp(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        // An explicit pattern, not a template: the template renders as
        // "Nov 15 at 21:00" in en_US, which does not fit a row and reads like a
        // sentence rather than a stamp.
        formatter.dateFormat = "d MMM HH:mm"
        return formatter.string(from: date)
    }

    /// The folder name a person would recognise, or nil when the agent recorded
    /// nothing (a chat-only session).
    public static func project(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let shortened = Redactor().shortenHome(cwd)
        return shortened.split(separator: "/").last.map(String.init) ?? shortened
    }
}
