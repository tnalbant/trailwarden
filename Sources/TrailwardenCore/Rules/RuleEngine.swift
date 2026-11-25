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
///    target", not "any rm -rf");
/// 5. when one match has both, they must hold for the same command of a command
///    line: a path among that command's tokens, and the pattern matching the
///    text from that command's start (so `\A` anchors at the command). In
///    `ls ~/.ssh && git status` the path belongs to `ls`, not to `git`.
///
/// Hits are de-duplicated per `(rule, session, normalized command)`, so the
/// timeline shows one entry per situation. A hit an allowance covers is kept and
/// marked `allowed`.
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
    public let allowances: [Allowance]
    private let compiled: [CompiledRule]

    public init(rules: [Rule], allowances: [Allowance] = []) throws {
        self.rules = rules
        self.allowances = allowances

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
        candidates: [String],
        segments: [CommandSegment]) -> Bool
    {
        if !match.tools.isEmpty, !match.tools.contains(where: { toolMatches($0, tool) }) {
            return false
        }
        if let regex = match.commandRegex, !match.globs.isEmpty, !segments.isEmpty {
            // Paths first: they are cheap, and most commands name no matching path.
            let matched = segments.contains { segment in
                (segment.candidates.contains { pathMatches(match, $0) }
                    || segment.directories.contains { pathMatches(match, $0) || isSecretDirectory($0) })
                    && regex.firstMatch(in: segment.line, range: segment.range) != nil
            }
            guard matched else { return false }
        } else {
            if let regex = match.commandRegex {
                guard texts.contains(where: { matches(regex, $0) }) else { return false }
            }
            if !match.globs.isEmpty {
                guard candidates.contains(where: { pathMatches(match, $0) }) else { return false }
            }
        }
        if !match.anyOf.isEmpty {
            return match.anyOf.contains {
                evaluate($0, tool: tool, texts: texts, candidates: candidates, segments: segments)
            }
        }
        return true
    }

    private static func pathMatches(_ match: CompiledMatch, _ candidate: String) -> Bool {
        match.globs.contains { Glob.matches($0, candidate) }
            && !match.excludes.contains { Glob.matches($0, candidate) }
    }

    /// Built-in catalogue with no allowances unless given. Used by the CLI and by tests.
    public static func builtIn(allowances: [Allowance] = []) throws -> RuleEngine {
        try RuleEngine(rules: RuleCatalog.builtIn(), allowances: allowances)
    }

    // MARK: - Evaluation

    /// An allowance is judged at the event's own time: one that has run out
    /// still covers what happened before its end, so a later re-grade never
    /// brings back a hit the reader already allowed.
    public func hits(for event: Event) -> [RiskHit] {
        // Heredoc bodies are file content (`cat > x <<EOF`), not commands — unless
        // they are fed to a shell, which `withoutHeredocBodies` keeps.
        if event.kind == .toolResult {
            return []
        }
        // What the agent ran is the command. A tool result is what came back and a
        // Bash description is what the agent said, so neither is scanned.
        let texts = Self.scannedTexts(for: event)
        let candidates = Self.pathCandidates(for: event)
        let segments = Self.commandSegments(for: event)
        let target = Self.target(for: event)

        let tool = Self.canonicalTool(event.tool)

        var result: [RiskHit] = []
        for rule in compiled {
            guard Self.evaluate(
                rule.match,
                tool: tool,
                texts: texts,
                candidates: candidates,
                segments: segments)
            else {
                continue
            }
            let allowed = isAllowed(rule.id, target: target, cwd: event.cwd, at: event.ts)
            result.append(RiskHit(
                ruleId: rule.id,
                severity: rule.severity,
                message: rule.message,
                allowed: allowed))
        }
        return result.sorted { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.ruleId < rhs.ruleId : lhs.severity > rhs.severity
        }
    }

    /// The text of an event that rules match against: the command with heredoc
    /// bodies removed. Preview is only used for tool calls that have no command.
    static func scannedTexts(for event: Event) -> [String] {
        if event.kind == .toolResult {
            return []
        }
        let source: String? = if let command = event.command, !command.isEmpty {
            command
        } else {
            event.preview
        }
        guard let source, !source.isEmpty else { return [] }
        return [withoutHeredocBodies(source)]
    }

    /// Returns the events with `risk` filled in, one hit per situation.
    public func annotate(_ events: [Event]) -> [Event] {
        var seen = Set<String>()
        return events.map { event in
            let target = Self.target(for: event)
            let hits = hits(for: event).filter { hit in
                seen.insert("\(hit.ruleId)|\(event.sessionId)|\(target)|\(hit.allowed)").inserted
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
        return hits(for: event)
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
            values.append(contentsOf: tokens(in: strippingQuotedArguments(withoutHeredocBodies(command))))
        }
        return values.map(normalizePathToken).filter { !$0.isEmpty }
    }

    /// One command of a command line: where it starts in the line (it runs to
    /// the line's end, so a pattern can see what it is piped into) and the
    /// path-like tokens of that command alone, plus the event's own paths.
    struct CommandSegment {
        let line: String
        let range: NSRange
        let candidates: [String]
        /// Where earlier `cd`/`pushd` commands of the line went.
        let directories: [String]
    }

    /// The commands of an event's command line, split at unquoted `;`, `&`,
    /// `&&`, `|`, `||` and newlines. Empty when there is no command, or when an
    /// edit tool's "command" is patch text.
    static func commandSegments(for event: Event) -> [CommandSegment] {
        guard event.kind != .toolResult, let command = event.command, !command.isEmpty else { return [] }
        let tool = canonicalTool(event.tool)
        if tool == "Write" || tool == "Edit", !event.paths.isEmpty {
            return []
        }
        let line = withoutHeredocBodies(command)
        let stripped = strippingQuotedArguments(line)
        let paths = event.paths.map(normalizePathToken).filter { !$0.isEmpty }
        func candidates(_ text: String) -> [String] {
            paths + tokens(in: text).map(normalizePathToken).filter { !$0.isEmpty }
        }
        let parts = splitCommandParts(line)
        let blanked = splitCommandParts(stripped)
        // Blanking quotes never adds or removes a separator; if it ever did, the
        // whole line counts as one command.
        guard parts.count == blanked.count else {
            return [
                CommandSegment(
                    line: line,
                    range: NSRange(line.startIndex..., in: line),
                    candidates: candidates(stripped),
                    directories: [])
            ]
        }
        var result: [CommandSegment] = []
        var start = line.startIndex
        var directories: [String] = []
        for (part, blank) in zip(parts, blanked) {
            result.append(
                CommandSegment(
                    line: line,
                    range: NSRange(start..., in: line),
                    candidates: candidates(blank.body),
                    directories: directories))
            directories = directoriesAfter(blank.body, previous: directories)
            start = line.index(
                start,
                offsetBy: part.body.count + part.delimiter.count,
                limitedBy: line.endIndex) ?? line.endIndex
        }
        return result
    }

    /// `cat > x.py <<'EOF' … EOF` carries a file's content, and content that
    /// mentions `id_rsa` or `rm -rf ~` is not a command that does it. Only the
    /// heredoc body is dropped; the command line around it still counts. A body
    /// fed to a shell (`bash <<EOF`, `ssh host <<EOF`) is a script and stays.
    private static let heredoc = try? NSRegularExpression(
        pattern: #"<<-?[ \t]*(['"]?)(\w+)\1[^\n]*\n[\s\S]*?\n[ \t]*\2[ \t]*(?=\n|$)"#)
    /// A heredoc whose body is run, not stored: fed to a shell or an interpreter
    /// before the `<<` (`bash <<EOF`, `python3 - <<EOF`) …
    private static let shellBeforeHeredoc = try? NSRegularExpression(
        pattern: #"\b(?:(?:ba|z|da|k|fi|c|tc)?sh|ssh|sudo|eval|source|python[0-9.]*|node|deno|bun|ruby|perl|php"#
            + #"|osascript|lua|tclsh|pwsh|Rscript|swift|"# + sqlClients + #")\b[^\n;&|]*$"#)
    /// Database shells: a heredoc fed to one is SQL that runs (`psql db <<EOF`).
    private static let sqlClients =
        #"psql|mysql|mariadb|sqlite3|duckdb|sqlcmd|clickhouse-client|mongosh|redis-cli|cqlsh"#
    /// … or piped into one after it, on the same line (`cat <<EOF | sh`).
    private static let shellAfterHeredoc = try? NSRegularExpression(
        pattern: #"^[^\n]*\|\s*(?:sudo\s+(?:-\S+\s+)*)?(?:\S*/)?"#
            +
            #"(?:(?:ba|z|da|k|fi|c|tc)?sh|python[0-9.]*|node|deno|bun|ruby|perl|php|osascript|lua|tclsh|pwsh"#
            + #"|xargs|swift|"# + sqlClients + #")\b"#)

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
            // The rest of the `<<WORD` line: what the body is piped into.
            let headerEnd = result[found.lowerBound...].firstIndex(of: "\n") ?? found.upperBound
            let trail = String(result[result.index(found.lowerBound, offsetBy: 2) ..< headerEnd])
            if let piped = shellAfterHeredoc,
               piped.firstMatch(in: trail, range: NSRange(trail.startIndex..., in: trail)) != nil
            {
                continue
            }
            result.replaceSubrange(found, with: "<<" + result[name])
        }
        return result
    }

    // MARK: - Quoted prose

    private static let messageFlagBefore = try? NSRegularExpression(
        pattern: #"(?:^|\s)(?:-m|--message)(?:=|\s*)$"#)
    private static let echoPart = try? NSRegularExpression(pattern: #"^\s*(?:echo|printf)\b"#)
    private static let interpreterPart = try? NSRegularExpression(
        pattern: #"^\s*(?:sudo\s+(?:-\S+\s+)*)?(?:\S*/)?(?:sh|bash|zsh|dash|python3?|perl|ruby|node|eval|base64|xargs)\b"#)
    private static let startupFileRedirect = try? NSRegularExpression(
        pattern: #">>?\s*["']?(?:~|\$\{?HOME\}?|/[\w/.-]*)?/?\.(?:zshrc|zshenv|zprofile|zlogin|bashrc|bash_profile|profile)\b"#)

    /// Removes text that is prose, not a command: the quoted argument of `-m` /
    /// `--message` and the quoted arguments of `echo` / `printf`. An `echo` that is
    /// piped into a shell, an interpreter or `xargs`, or redirected into a shell
    /// startup file, keeps its text because that text runs or is used as paths.
    static func strippingQuotedArguments(_ command: String) -> String {
        guard command.contains("-m") || command.contains("echo") || command.contains("printf") else {
            return command
        }
        let parts = splitCommandParts(command)
        var result = ""
        for (index, part) in parts.enumerated() {
            var body = part.body
            // A command substitution runs, whatever quotes surround it.
            if !body.contains("$("), !body.contains("`") {
                let isEcho = isMatch(echoPart, body) && !runsItsText(parts, from: index, body: body)
                body = blankingQuotes(body, allQuoted: isEcho)
            }
            result += body + part.delimiter
        }
        return result
    }

    private static func isMatch(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func runsItsText(
        _ parts: [(body: String, delimiter: String)],
        from index: Int,
        body: String) -> Bool
    {
        if isMatch(startupFileRedirect, body) {
            return true
        }
        var next = index
        while parts[next].delimiter == "|", next + 1 < parts.count {
            next += 1
            if isMatch(interpreterPart, parts[next].body) {
                return true
            }
        }
        return false
    }

    /// Splits at unquoted `;`, `&`, `&&`, `|`, `||` and newlines, keeping the delimiters.
    private static func splitCommandParts(_ text: String) -> [(body: String, delimiter: String)] {
        let chars = Array(text)
        var parts: [(body: String, delimiter: String)] = []
        var current = ""
        var quote: Character?
        var index = 0
        func flush(_ delimiter: String) {
            parts.append((current, delimiter))
            current = ""
            index += delimiter.count
        }
        while index < chars.count {
            let char = chars[index]
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            if let open = quote {
                current.append(char)
                if char == "\\", open == "\"", let next {
                    current.append(next)
                    index += 2
                    continue
                }
                if char == open {
                    quote = nil
                }
                index += 1
                continue
            }
            switch char {
            case "\"", "'":
                quote = char
                current.append(char)
                index += 1
            case "\\":
                current.append(char)
                if let next {
                    current.append(next)
                }
                index += 2
            case ";", "\n":
                flush(String(char))
            case "&" where current.last == ">" || current.last == "<":
                current.append(char)
                index += 1
            case "&", "|":
                flush(next == char ? String([char, char]) : String(char))
            default:
                current.append(char)
                index += 1
            }
        }
        parts.append((current, ""))
        return parts
    }

    /// Replaces closed quoted strings with an empty pair: every one when
    /// `allQuoted`, else only the argument of an unquoted `-m` / `--message`.
    /// A redirect target (`> "file"`) is a path and is never blanked.
    private static func blankingQuotes(_ body: String, allQuoted: Bool) -> String {
        var result = ""
        var index = body.startIndex
        while index < body.endIndex {
            let char = body[index]
            guard char == "\"" || char == "'" else {
                result.append(char)
                index = body.index(after: index)
                continue
            }
            var end = body.index(after: index)
            while end < body.endIndex, body[end] != char {
                if char == "\"", body[end] == "\\" {
                    end = body.index(after: end)
                    if end == body.endIndex {
                        break
                    }
                }
                end = body.index(after: end)
            }
            guard end < body.endIndex else {
                result += body[index...]
                break
            }
            let lastSignificant = result.last { !$0.isWhitespace }
            let isRedirectTarget = lastSignificant == ">" || lastSignificant == "<"
            if !isRedirectTarget, allQuoted || isMatch(messageFlagBefore, result) {
                result += "\(char)\(char)"
            } else {
                result += body[index ... end]
            }
            index = body.index(after: end)
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

    private func isAllowed(_ ruleId: String, target: String, cwd: String?, at date: Date) -> Bool {
        allowances.contains { $0.isActive(at: date) && $0.covers(ruleId: ruleId, target: target, cwd: cwd) }
    }
}
