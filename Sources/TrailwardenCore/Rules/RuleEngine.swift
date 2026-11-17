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
    /// One `RuleMatch`, compiled. Alternatives are compiled the same way, so an
    /// `anyOf` entry has exactly the semantics of a top-level match.
    private struct CompiledMatch: @unchecked Sendable {
        let tools: [String]
        let commandRegex: NSRegularExpression?
        let globs: [NSRegularExpression]
        let excludes: [NSRegularExpression]
        let anyOf: [CompiledMatch]

        /// A match with no condition at all would flag every event; such a rule
        /// is skipped instead.
        var isEmpty: Bool {
            commandRegex == nil && globs.isEmpty && anyOf.isEmpty
        }
    }

    private struct CompiledRule: @unchecked Sendable {
        let id: String
        let severity: Severity
        let message: String
        let match: CompiledMatch
    }

    public let rules: [Rule]
    public let mutes: [Mute]
    private let compiled: [CompiledRule]

    public init(rules: [Rule], mutes: [Mute] = []) throws {
        self.rules = rules
        self.mutes = mutes

        var compiled: [CompiledRule] = []
        for rule in rules where rule.isEnabled {
            let match = try Self.compile(rule.match, ruleId: rule.id)
            if match.isEmpty {
                continue
            }
            compiled.append(
                CompiledRule(
                    id: rule.id,
                    severity: rule.severity,
                    message: rule.message,
                    match: match))
        }
        self.compiled = compiled
    }

    private static func compile(_ match: RuleMatch, ruleId: String) throws -> CompiledMatch {
        var regex: NSRegularExpression?
        if let pattern = match.commandRegex {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                // `^` matches at every line: a multi-line script is a list of
                // commands, and the second line runs just like the first.
                options: [.caseInsensitive, .anchorsMatchLines])
            else {
                throw RuleError.invalidPattern(ruleId)
            }
            regex = expression
        }
        func globs(_ patterns: [String]?) throws -> [NSRegularExpression] {
            try (patterns ?? []).map { pattern in
                guard let expression = Glob.regex(for: normalizeGlob(pattern)) else {
                    throw RuleError.invalidGlob(ruleId: ruleId, pattern: pattern)
                }
                return expression
            }
        }
        return try CompiledMatch(
            tools: match.tool.map { $0.split(separator: "|").map(String.init) } ?? [],
            commandRegex: regex,
            globs: globs(match.pathGlobs),
            excludes: globs(match.excludePathGlobs),
            anyOf: (match.anyOf ?? []).map { try compile($0, ruleId: ruleId) })
    }

    private static func evaluate(
        _ match: CompiledMatch,
        tool: String?,
        texts: [String],
        candidates: [String]) -> Bool
    {
        if !match.tools.isEmpty, !match.tools.contains(where: { toolMatches($0, tool) }) {
            return false
        }
        if let regex = match.commandRegex {
            guard texts.contains(where: { matches(regex, $0) }) else { return false }
        }
        if !match.globs.isEmpty {
            let matched = candidates.contains { candidate in
                match.globs.contains { Glob.matches($0, candidate) }
                    && !match.excludes.contains { Glob.matches($0, candidate) }
            }
            guard matched else { return false }
        }
        if !match.anyOf.isEmpty {
            return match.anyOf.contains {
                evaluate($0, tool: tool, texts: texts, candidates: candidates)
            }
        }
        return true
    }

    /// Built-in catalogue with no mutes. Used by the CLI and by tests.
    public static func builtIn(mutes: [Mute] = []) throws -> RuleEngine {
        try RuleEngine(rules: RuleCatalog.builtIn(), mutes: mutes)
    }

    // MARK: - Evaluation

    public func hits(for event: Event, now: Date = Date()) -> [RiskHit] {
        // Heredoc bodies are file content (`cat > x <<EOF`), not commands — unless
        // they are fed to a shell, which `withoutHeredocBodies` keeps.
        let texts = [event.command, event.preview].compactMap(\.self)
            .filter { !$0.isEmpty }
            .map(Self.withoutHeredocBodies)
        let candidates = Self.pathCandidates(for: event)
        let target = Self.target(for: event)

        let tool = Self.canonicalTool(event.tool)

        var result: [RiskHit] = []
        for rule in compiled {
            guard Self.evaluate(rule.match, tool: tool, texts: texts, candidates: candidates) else {
                continue
            }
            if isMuted(rule.id, target: target, now: now) {
                continue
            }
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
        now: Date = Date()) -> [RiskHit]
    {
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
            rawJSON: nil)
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
    /// The same action has a different name in every agent: codex says `exec`,
    /// Gemini says `run_shell_command`, Claude says `Bash`. Rules are written
    /// against the canonical name, so a rule that covers `Bash` covers all three.
    public static func canonicalTool(_ tool: String?) -> String? {
        guard let tool else { return nil }
        switch tool {
        case "run_shell_command", "shell", "bash", "exec", "exec_command", "local_shell",
             "terminal", "list_directory", "glob", "grep_search", "run_terminal_command_v2",
             "run_terminal_cmd", "powershell":
            return "Bash"
        case "read_file", "read_many_files", "read", "view", "read_file_v2":
            return "Read"
        case "write_file", "write", "create_file", "apply_patch", "create":
            return "Write"
        case "replace", "edit", "edit_file", "str_replace", "apply_diff", "patch", "MultiEdit",
             "NotebookEdit", "edit_file_v2", "search_replace", "str_replace_editor":
            return "Edit"
        default:
            return tool
        }
    }

    public static func target(for event: Event) -> String {
        let command = normalizedCommand(event.command ?? "")
        if !command.isEmpty {
            return command
        }
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
        // An edit tool's "command" is the patch text — file content, not paths.
        // Its structured paths already say which files it touched.
        let tool = canonicalTool(event.tool)
        let isEdit = tool == "Write" || tool == "Edit"
        if let command = event.command, !(isEdit && !event.paths.isEmpty) {
            values.append(contentsOf: tokens(in: withoutHeredocBodies(command)))
        }
        return values.map(normalizePathToken).filter { !$0.isEmpty }
    }

    /// `cat > x.py <<'EOF' … EOF` carries a file's content, and content that
    /// mentions `id_rsa` or `rm -rf ~` is not a command that does it. Only the
    /// heredoc body is dropped; the command line around it still counts. A body
    /// fed to a shell (`bash <<EOF`, `ssh host <<EOF`) is a script and stays.
    private static let heredoc = try? NSRegularExpression(
        pattern: #"<<-?[ \t]*(['"]?)(\w+)\1[^\n]*\n[\s\S]*?\n[ \t]*\2[ \t]*(?=\n|$)"#)
    private static let shellBeforeHeredoc = try? NSRegularExpression(
        pattern: #"\b(?:(?:ba|z|da|k)?sh|ssh|sudo)\b[^\n;&|]*$"#)

    static func withoutHeredocBodies(_ command: String) -> String {
        guard command.contains("<<"), let heredoc else { return command }
        var result = command
        let range = NSRange(result.startIndex..., in: result)
        for match in heredoc.matches(in: result, range: range).reversed() {
            guard let found = Range(match.range, in: result),
                  let name = Range(match.range(at: 2), in: result)
            else { continue }
            let lineStart = result[..<found.lowerBound].lastIndex(of: "\n").map { result.index(after: $0) }
                ?? result.startIndex
            let lead = String(result[lineStart ..< found.lowerBound])
            if let shell = shellBeforeHeredoc,
               shell.firstMatch(in: lead, range: NSRange(lead.startIndex..., in: lead)) != nil
            {
                continue
            }
            result.replaceSubrange(found, with: "<<" + result[name])
        }
        return result
    }

    static func tokens(in command: String) -> [String] {
        command
            .split(whereSeparator: { $0.isWhitespace || $0 == ";" || $0 == "|" || $0 == "&" })
            .map(String.init)
    }

    static func normalizePathToken(_ raw: String) -> String {
        var token = raw
        while let first = token.first, first == "\"" || first == "'" {
            token.removeFirst()
        }
        while let last = token.last, last == "\"" || last == "'" {
            token.removeLast()
        }
        return expandHome(token)
    }

    static func normalizeGlob(_ pattern: String) -> String {
        expandHome(pattern)
    }

    private static func expandHome(_ value: String) -> String {
        if value.hasPrefix("${HOME}") {
            return "~" + value.dropFirst("${HOME}".count)
        }
        if value.hasPrefix("$HOME") {
            return "~" + value.dropFirst("$HOME".count)
        }
        // Edit tools record absolute paths (`/Users/demo/.zshrc`); rules are written
        // against `~` so they hold on every machine.
        for root in ["/Users/", "/home/"] where value.hasPrefix(root) {
            let rest = value.dropFirst(root.count)
            guard let slash = rest.firstIndex(of: "/") else { return "~" }
            return "~" + rest[slash...]
        }
        return value
    }

    private func isMuted(_ ruleId: String, target: String, now: Date) -> Bool {
        mutes.contains { $0.ruleId == ruleId && $0.target == target && $0.isActive(at: now) }
    }
}
