// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// How aggressively text is scrubbed before it is stored, shown or exported.
public enum RedactionLevel: String, Codable, Sendable, CaseIterable {
    /// Credentials and key material. Keeps paths readable.
    case normal
    /// `normal` plus e-mail addresses and user names in home paths.
    case strict
}

/// Masking pass for everything that leaves the store: previews, commands, raw
/// JSON lines and exported reports.
///
/// Patterns run most-specific first, so a GitHub token is reported as a token
/// rather than swallowed by the generic long-blob rule.
public struct Redactor: Sendable {
    public let level: RedactionLevel

    public init(level: RedactionLevel = .normal) {
        self.level = level
    }

    // MARK: - Rules

    struct Rule {
        let regex: NSRegularExpression
        let template: String
        /// Matches this returns `true` for are left alone.
        var keep: (@Sendable (Substring) -> Bool)?
        /// ASCII text every match must contain (lowercase; compared without
        /// case). A text without it cannot match, so the regex is skipped:
        /// raw transcript lines run to megabytes, and most hold no secret.
        var hint: [UInt8]?
    }

    private static func compile(
        _ pattern: String,
        _ template: String,
        hint: String? = nil,
        options: NSRegularExpression.Options = []) -> Rule?
    {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return Rule(regex: regex, template: template, hint: hint.map { Array($0.lowercased().utf8) })
    }

    /// Whether `text` contains the ASCII `needle`, ignoring case. A byte scan,
    /// far cheaper than a regex pass over a long line.
    static func mayContain(_ text: String, _ needle: [UInt8]) -> Bool {
        guard let first = needle.first else { return true }
        var text = text
        return text.withUTF8 { bytes in
            let count = bytes.count, length = needle.count
            guard length <= count else { return false }
            var index = 0
            while index <= count - length {
                if bytes[index] | 0x20 == first | 0x20 {
                    var matched = 1
                    while matched < length, bytes[index + matched] | 0x20 == needle[matched] | 0x20 {
                        matched += 1
                    }
                    if matched == length {
                        return true
                    }
                }
                index += 1
            }
            return false
        }
    }

    /// Shared by both levels. Specific shapes first, so a known token is named
    /// for what it is before the generic long-blob rule sees it.
    static let baseRules: [Rule] = [
        // PEM key material, header to footer — or to the end of the text when the
        // footer is missing: previews are cut to a few hundred characters, and a
        // key printed by `cat ~/.ssh/id_rsa` loses its footer in the cut.
        compile(
            "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\\z)",
            "[redacted:private-key]",
            hint: "-----BEGIN "),
        compile("\\bsk-[A-Za-z0-9_-]{16,}", "[redacted:openai-key]", hint: "sk-"),
        compile("\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}", "[redacted:github-token]", hint: "gh"),
        compile("\\bgithub_pat_[A-Za-z0-9_]{20,}", "[redacted:github-token]", hint: "github_pat_"),
        compile("\\bglpat-[A-Za-z0-9_-]{20,}", "[redacted:gitlab-token]", hint: "glpat-"),
        compile("\\bAKIA[0-9A-Z]{16}\\b", "[redacted:aws-key]", hint: "akia"),
        compile("\\bAIza[0-9A-Za-z_-]{35}", "[redacted:google-key]", hint: "aiza"),
        compile("\\bxox[baprs]-[A-Za-z0-9-]{10,}", "[redacted:slack-token]", hint: "xox"),
        compile("\\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}", "[redacted:stripe-key]", hint: "k_"),
        compile("\\bnpm_[A-Za-z0-9]{36}\\b", "[redacted:npm-token]", hint: "npm_"),
        compile("\\bhf_[A-Za-z0-9]{30,}", "[redacted:huggingface-token]", hint: "hf_"),
        // JSON Web Tokens: three base64url parts, the first always a JSON header.
        compile(
            "\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}",
            "[redacted:jwt]",
            hint: "eyj"),
        // `Authorization: Bearer x` as a header line, a JSON field or a curl flag.
        compile(
            "(?i)(authorization[\"']?\\s*[:=]\\s*[\"']?\\s*bearer\\s+)[A-Za-z0-9._~+/=-]+",
            "$1[redacted:bearer]",
            hint: "bearer"),
        // A password inside a URL: scheme://user:secret@host. The password may
        // itself hold `@` or `/`, so it runs to the `@` that is followed by a
        // host (and optional port) and then the end of the authority.
        compile(
            "(://[^/\\s:@'\"]+:)[^\\s'\"]{1,256}?@(?=[A-Za-z0-9.\\-\\[\\]:]+(?:[/?#\\s'\"]|$))",
            "$1[redacted:password]@",
            hint: "://"),
        // Long base64-ish blobs: certificates, encoded credentials, dumps.
        compile("\\b[A-Za-z0-9+/]{64,}={0,2}", "[redacted:blob]").map { rule in
            var rule = rule
            rule.keep = isPathLike
            return rule
        }
    ].compactMap(\.self)

    /// Base64 and a long file path share an alphabet, so a deep path would be
    /// stored as `/[redacted:blob]` without this. A path has many short segments
    /// of mostly lower-case words; base64 has a slash only every 64 characters or
    /// so, by chance, and is dense with digits and capitals. All three must look
    /// like a path before a match is kept — a credential that merely happens to
    /// contain three slashes is still masked.
    @Sendable static func isPathLike(_ text: Substring) -> Bool {
        let segments = text.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 4, segments.allSatisfy({ $0.count <= 48 }) else { return false }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let digits = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let capitals = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        let length = max(1, text.unicodeScalars.count)
        return Double(digits) / Double(length) <= 0.08
            && Double(capitals) / Double(max(1, letters.count)) <= 0.3
    }

    /// Only applied at `.strict`.
    static let strictRules: [Rule] = [
        compile("\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b", "[redacted:email]"),
        compile("/(?:Users|home)/[^/\\s\"']+", "~")
    ].compactMap(\.self)

    static var ruleCount: Int {
        baseRules.count + strictRules.count
    }

    private var activeRules: [Rule] {
        switch level {
        case .normal: Self.baseRules
        case .strict: Self.baseRules + Self.strictRules
        }
    }

    // MARK: - Redaction

    public func redact(_ text: String) -> String {
        var result = text
        for rule in activeRules {
            if let hint = rule.hint, !Self.mayContain(result, hint) {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            if let keep = rule.keep {
                // Replace from the end so earlier ranges stay valid.
                for match in rule.regex.matches(in: result, range: range).reversed() {
                    guard let found = Range(match.range, in: result), !keep(result[found]) else { continue }
                    result.replaceSubrange(found, with: rule.template)
                }
                continue
            }
            result = rule.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: rule.template)
        }
        return result
    }

    /// `/Users/<name>/work` -> `~/work` (and `/home/<name>` on Linux exports).
    public func shortenHome(_ path: String) -> String {
        let range = NSRange(path.startIndex..., in: path)
        guard let rule = Self.strictRules.last else { return path }
        return rule.regex.stringByReplacingMatches(
            in: path,
            options: [],
            range: range,
            withTemplate: "~")
    }

    /// Redacts an event without touching identity or classification: the same id,
    /// time, agent, kind, tool and rule hits survive so the record stays auditable.
    /// Paths stay absolute here — the store keeps the real location, exports shorten it.
    public func redact(_ event: Event) -> Event {
        Event(
            id: event.id,
            ts: event.ts,
            agent: event.agent,
            sessionId: event.sessionId,
            kind: event.kind,
            cwd: event.cwd.map(redact),
            gitBranch: event.gitBranch.map(redact),
            tool: event.tool,
            command: event.command.map(redact),
            paths: event.paths.map(redact),
            preview: event.preview.map(redact),
            risk: event.risk,
            rawJSON: event.rawJSON.map(redact),
            usage: event.usage)
    }

    /// What leaves the machine: secrets masked *and* the user name in home paths
    /// shortened to `~`.
    public func redactForExport(_ event: Event) -> Event {
        let base = redact(event)
        return Event(
            id: base.id,
            ts: base.ts,
            agent: base.agent,
            sessionId: base.sessionId,
            kind: base.kind,
            cwd: base.cwd.map(shortenHome),
            gitBranch: base.gitBranch,
            tool: base.tool,
            command: base.command.map(shortenHome),
            paths: base.paths.map(shortenHome),
            // Many previews are a path or a command; the user name goes too.
            preview: base.preview.map(shortenHome),
            risk: base.risk,
            rawJSON: base.rawJSON,
            usage: base.usage)
    }
}
