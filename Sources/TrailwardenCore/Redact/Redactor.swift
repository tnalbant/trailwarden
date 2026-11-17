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

    /// Shared by both levels.
    static let baseRules: [Rule] = [
        // PEM key material, header to footer.
        compile(
            "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
            "[redacted:private-key]",
            hint: "-----BEGIN "),
        compile("\\bsk-[A-Za-z0-9_-]{16,}", "[redacted:openai-key]", hint: "sk-"),
        compile("\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}", "[redacted:github-token]", hint: "gh"),
        compile("\\bgithub_pat_[A-Za-z0-9_]{20,}", "[redacted:github-token]", hint: "github_pat_"),
        compile("\\bAKIA[0-9A-Z]{16}\\b", "[redacted:aws-key]", hint: "akia"),
        compile("\\bxox[baprs]-[A-Za-z0-9-]{10,}", "[redacted:slack-token]", hint: "xox"),
        compile(
            "(?i)(authorization:\\s*bearer\\s+)[A-Za-z0-9._~+/=-]+",
            "$1[redacted:bearer]",
            hint: "bearer"),
        // Long base64-ish blobs: certificates, encoded credentials, dumps.
        compile("\\b[A-Za-z0-9+/]{64,}={0,2}", "[redacted:blob]").map { rule in
            var rule = rule
            rule.keep = isPathLike
            return rule
        }
    ].compactMap(\.self)

    /// Base64 and a long file path share an alphabet. A path has short segments
    /// between many slashes (`Users/me/Desktop/App/Sources/Feature/View.swift`);
    /// an encoded blob has a slash every 64 characters or so, by chance. Without
    /// this, every deep path in the index was stored as `/[redacted:blob]`.
    @Sendable static func isPathLike(_ text: Substring) -> Bool {
        let segments = text.split(separator: "/", omittingEmptySubsequences: false)
        return segments.count >= 4 && segments.allSatisfy { $0.count <= 48 }
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
            gitBranch: event.gitBranch,
            tool: event.tool,
            command: event.command.map(redact),
            paths: event.paths.map(redact),
            preview: event.preview.map(redact),
            risk: event.risk,
            rawJSON: event.rawJSON.map(redact))
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
            preview: base.preview,
            risk: base.risk,
            rawJSON: base.rawJSON)
    }
}
