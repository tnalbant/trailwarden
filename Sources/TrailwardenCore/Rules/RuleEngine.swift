// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Applies the rule set to events.
///
/// Semantics, in order:
/// 1. a rule with a `tool` only applies to that tool;
/// 2. a rule with a `commandRegex` must match the command or preview text;
/// 3. a rule with `pathGlobs` must match one of the event's paths or one of the
///    path-like tokens of its command;
/// 4. both conditions, when present, must hold (R1 is "rm -rf *and* a dangerous
///    target", not "any rm -rf").
///
/// Hits are de-duplicated per `(rule, session, normalized command)` and muted
/// pairs are dropped, so the timeline shows one entry per situation.
public struct RuleEngine: Sendable {
    private struct CompiledRule: @unchecked Sendable {
        let id: String
        let severity: Severity
        let message: String
        let tool: String?
        let commandRegex: NSRegularExpression?
        let globs: [NSRegularExpression]
    }

    public let rules: [Rule]
    public let mutes: [Mute]
    private let compiled: [CompiledRule]

    public init(rules: [Rule], mutes: [Mute] = []) throws {
        self.rules = rules
        self.mutes = mutes

        var compiled: [CompiledRule] = []
        for rule in rules where rule.isEnabled {
            var regex: NSRegularExpression?
            if let pattern = rule.match.commandRegex {
                guard let expression = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ) else {
                    throw RuleError.invalidPattern(rule.id)
                }
                regex = expression
            }
            var globs: [NSRegularExpression] = []
            for pattern in rule.match.pathGlobs ?? [] {
                let normalized = Self.normalizeGlob(pattern)
                guard let expression = Glob.regex(for: normalized) else {
                    throw RuleError.invalidGlob(ruleId: rule.id, pattern: pattern)
                }
                globs.append(expression)
            }
            if regex == nil && globs.isEmpty { continue }
            compiled.append(
                CompiledRule(
                    id: rule.id,
                    severity: rule.severity,
                    message: rule.message,
                    tool: rule.match.tool,
                    commandRegex: regex,
                    globs: globs
                )
            )
        }
        self.compiled = compiled
    }

    /// Built-in catalogue with no mutes. Used by the CLI and by tests.
    public static func builtIn(mutes: [Mute] = []) throws -> RuleEngine {
        try RuleEngine(rules: RuleCatalog.builtIn(), mutes: mutes)
    }

    // MARK: - Evaluation

    public func hits(for event: Event, now: Date = Date()) -> [RiskHit] {
        let texts = [event.command, event.preview].compactMap { $0 }.filter { !$0.isEmpty }
        let candidates = Self.pathCandidates(for: event)
        let target = Self.target(for: event)

        var result: [RiskHit] = []
        for rule in compiled {
            if let tool = rule.tool, !Self.toolMatches(tool, event.tool) { continue }
            if let regex = rule.commandRegex {
                guard texts.contains(where: { Self.matches(regex, $0) }) else { continue }
            }
            if !rule.globs.isEmpty {
                let matched = candidates.contains { candidate in
                    rule.globs.contains { Glob.matches($0, candidate) }
                }
                guard matched else { continue }
            }
            if isMuted(rule.id, target: target, now: now) { continue }
            result.append(RiskHit(ruleId: rule.id, severity: rule.severity, message: rule.message))
        }
        return result.sorted { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.ruleId < rhs.ruleId : lhs.severity > rhs.severity
        }
    }

    /// Returns the events with `risk` filled in, one hit per situation.
    public func annotate(_ events: [Event], now: Date = Date()) -> [Event] {
        var seen = Set<String>()
        return events.map { event in
            let target = Self.target(for: event)
            let hits = hits(for: event, now: now).filter { hit in
                seen.insert("\(hit.ruleId)|\(event.sessionId)|\(target)").inserted
            }
            return event.withRisk(hits)
        }
    }

    /// Evaluates a single command, for `trailwarden rules test`.
    public func evaluateCommand(
        _ command: String,
        tool: String = "Bash",
        now: Date = Date()
    ) -> [RiskHit] {
        let event = Event(
            id: "preview",
            ts: now,
            agent: .claudeCode,
            sessionId: "preview",
            kind: .toolCall,
            tool: tool,
            command: command,
            preview: command,
            risk: [],
            rawJSON: nil
        )
        return hits(for: event, now: now)
    }

    // MARK: - Matching helpers

    static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    static func toolMatches(_ expected: String, _ actual: String?) -> Bool {
        guard let actual else { return false }
        return actual.caseInsensitiveCompare(expected) == .orderedSame
    }

    /// The identity used for muting and de-duplication: the command with runs of
    /// whitespace collapsed, or the first path when there is no command.
    public static func target(for event: Event) -> String {
        let command = normalizedCommand(event.command ?? "")
        if !command.isEmpty { return command }
        return event.paths.first ?? event.kind.rawValue
    }

    public static func normalizedCommand(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Paths mentioned by an event: its structured paths plus the path-like tokens
    /// of its command. Preview text is deliberately excluded — file content is not
    /// a path.
    static func pathCandidates(for event: Event) -> [String] {
        var values = event.paths
        if let command = event.command {
            values.append(contentsOf: tokens(in: command))
        }
        return values.map(normalizePathToken).filter { !$0.isEmpty }
    }

    static func tokens(in command: String) -> [String] {
        command
            .split(whereSeparator: { $0.isWhitespace || $0 == ";" || $0 == "|" || $0 == "&" })
            .map(String.init)
    }

    static func normalizePathToken(_ raw: String) -> String {
        var token = raw
        while let first = token.first, first == "\"" || first == "'" { token.removeFirst() }
        while let last = token.last, last == "\"" || last == "'" { token.removeLast() }
        return expandHome(token)
    }

    static func normalizeGlob(_ pattern: String) -> String {
        expandHome(pattern)
    }

    private static func expandHome(_ value: String) -> String {
        if value.hasPrefix("${HOME}") { return "~" + value.dropFirst("${HOME}".count) }
        if value.hasPrefix("$HOME") { return "~" + value.dropFirst("$HOME".count) }
        return value
    }

    private func isMuted(_ ruleId: String, target: String, now: Date) -> Bool {
        mutes.contains { $0.ruleId == ruleId && $0.target == target && $0.isActive(at: now) }
    }
}
