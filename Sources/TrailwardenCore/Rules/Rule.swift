// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Conditions a rule can test. Missing conditions are "no constraint"; when both
/// a command pattern and path globs are present they must *both* hold.
public struct RuleMatch: Codable, Sendable, Equatable {
    /// Tool name the rule applies to, e.g. `Bash`; `nil` means every tool.
    public let tool: String?
    /// Regular expression over the command and preview text.
    public let commandRegex: String?
    /// Globs matched against the event's paths and the path-like tokens of its command.
    public let pathGlobs: [String]?

    public init(tool: String? = nil, commandRegex: String? = nil, pathGlobs: [String]? = nil) {
        self.tool = tool
        self.commandRegex = commandRegex
        self.pathGlobs = pathGlobs
    }
}

/// One entry of `rules.json`.
public struct Rule: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let severity: Severity
    public let match: RuleMatch
    public let message: String
    /// User rules may switch a built-in rule off without deleting it.
    public let enabled: Bool?

    public init(
        id: String,
        title: String,
        severity: Severity,
        match: RuleMatch,
        message: String,
        enabled: Bool? = nil)
    {
        self.id = id
        self.title = title
        self.severity = severity
        self.match = match
        self.message = message
        self.enabled = enabled
    }

    public var isEnabled: Bool {
        enabled ?? true
    }
}

/// A silenced `(rule, target)` pair. `target` is the normalized command (or the
/// first path when there is no command), so muting is per situation, not global.
public struct Mute: Codable, Sendable, Hashable, Identifiable {
    public let ruleId: String
    public let target: String
    /// The mute stops applying after this moment.
    public let until: Date

    public var id: String {
        "\(ruleId)|\(target)"
    }

    public init(ruleId: String, target: String, until: Date) {
        self.ruleId = ruleId
        self.target = target
        self.until = until
    }

    public func isActive(at date: Date) -> Bool {
        until > date
    }
}

public enum RuleError: Error, CustomStringConvertible, Sendable {
    case missingCatalog
    case invalidPattern(String)
    case invalidGlob(ruleId: String, pattern: String)

    public var description: String {
        switch self {
        case .missingCatalog: "rules.json is missing from the resource bundle"
        case let .invalidPattern(ruleId): "rule \(ruleId) has an invalid command pattern"
        case let .invalidGlob(ruleId, pattern): "rule \(ruleId) has an invalid path glob: \(pattern)"
        }
    }
}
