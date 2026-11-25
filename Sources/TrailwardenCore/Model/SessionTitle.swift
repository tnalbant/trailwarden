// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// A human name for a session: what the agent called it, or else what the
/// user first asked. Always redacted, one line, at most `limit` characters.
public struct SessionTitle: Sendable, Equatable {
    public enum Source: String, Sendable {
        /// The agent's own title (Claude Code `summary` / `ai-title` records).
        case summary
        /// The first thing the user typed.
        case firstMessage
    }

    public let text: String
    public let source: Source

    public init(text: String, source: Source) {
        self.text = text
        self.source = source
    }

    public static let limit = 60

    /// Wrapper text the agents put in front of the real prompt.
    private static let boilerplatePrefixes = [
        "<command-", "<local-command", "<system-reminder", "<environment_context", "<user_instructions",
        "<ide_", "<user-prompt-submit-hook", "caveat:", "# agents.md", "[request interrupted"
    ]

    /// First non-empty line, whitespace collapsed, redacted, cut on a word
    /// boundary. `nil` when nothing readable is left, or the text is wrapper
    /// boilerplate rather than something the user wrote.
    public static func fromFirstMessage(_ raw: String) -> SessionTitle? {
        make(raw, source: .firstMessage, skipBoilerplate: true)
    }

    /// An agent-written title, tidied the same way.
    static func fromSummary(_ raw: String) -> SessionTitle? {
        make(raw, source: .summary, skipBoilerplate: false)
    }

    private static func make(_ raw: String, source: Source, skipBoilerplate: Bool) -> SessionTitle? {
        let firstLine = raw.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .first { !$0.isEmpty }
        guard let firstLine else { return nil }
        if skipBoilerplate {
            let lowered = firstLine.lowercased()
            if boilerplatePrefixes.contains(where: { lowered.hasPrefix($0) }) {
                return nil
            }
        }
        // Redact before cutting, so a secret is never split into two halves
        // that no longer match a pattern.
        let line = Redactor().redact(firstLine)
        guard !line.isEmpty else { return nil }
        return SessionTitle(text: cut(line), source: source)
    }

    private static func cut(_ line: String) -> String {
        guard line.count > limit else { return line }
        let head = String(line.prefix(limit))
        var kept = head
        let nextIsSpace = line[line.index(line.startIndex, offsetBy: limit)] == " "
        if !nextIsSpace, let space = head.lastIndex(of: " ") {
            kept = String(head[..<space])
        }
        return kept.trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Collects the best title per session while a parser walks a file or a table.
struct TitleCollector {
    private(set) var titles: [String: SessionTitle] = [:]

    /// The first usable user message of a session; later ones are ignored.
    mutating func firstMessage(_ raw: String?, session: String) {
        guard !session.isEmpty, titles[session] == nil, let raw,
              let title = SessionTitle.fromFirstMessage(raw) else { return }
        titles[session] = title
    }

    /// An agent title beats any first message; a later one beats an earlier one.
    mutating func summary(_ raw: String?, session: String) {
        guard !session.isEmpty, let raw, let title = SessionTitle.fromSummary(raw) else { return }
        titles[session] = title
    }
}
