// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Conditions a rule can test. Missing conditions are "no constraint"; when both
/// a command pattern and path globs are present they must *both* hold.
public struct RuleMatch: Codable, Sendable, Equatable {
    /// Tool name the rule applies to, e.g. `Bash`; `nil` means every tool.
    /// Several tools are written `Write|Edit`.
    public let tool: String?
    /// Regular expression over the command and preview text.
    public let commandRegex: String?
    /// Globs matched against the event's paths and the path-like tokens of its command.
    public let pathGlobs: [String]?
    /// A path that matches one of these never satisfies `pathGlobs`, so
    /// `.env.example` can be told apart from `.env`.
    public let excludePathGlobs: [String]?
    /// Alternatives: the rule holds when its own conditions hold *and* at least
    /// one alternative does. One rule can then cover "the shell appends to
    /// ~/.zshrc" and "the edit tool rewrites ~/.zshrc" under a single id.
    public let anyOf: [RuleMatch]?

    public init(
        tool: String? = nil,
        commandRegex: String? = nil,
        pathGlobs: [String]? = nil,
        excludePathGlobs: [String]? = nil,
        anyOf: [RuleMatch]? = nil)
    {
        self.tool = tool
        self.commandRegex = commandRegex
        self.pathGlobs = pathGlobs
        self.excludePathGlobs = excludePathGlobs
        self.anyOf = anyOf
    }

    /// Every tool the match (or any alternative) names, for the rules screen.
    public var allTools: [String] {
        var result = tool.map { $0.split(separator: "|").map(String.init) } ?? []
        for alternative in anyOf ?? [] {
            result.append(contentsOf: alternative.allTools)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    /// Every command pattern, own and alternative.
    public var allCommandPatterns: [String] {
        (commandRegex.map { [$0] } ?? []) + (anyOf ?? []).flatMap(\.allCommandPatterns)
    }

    /// Every path glob, own and alternative, each once (two alternatives may
    /// share a list).
    public var allPathGlobs: [String] {
        var seen = Set<String>()
        return ((pathGlobs ?? []) + (anyOf ?? []).flatMap(\.allPathGlobs)).filter { seen.insert($0).inserted }
    }
}

/// Commands (or, for a rule that only looks at paths, file paths) that show
/// what a rule is for: each `matches` entry must raise the rule and no
/// `ignores` entry may. `RuleExamplesTests` holds every built-in rule to them.
public struct RuleExamples: Codable, Sendable, Equatable {
    public let matches: [String]
    public let ignores: [String]

    public init(matches: [String], ignores: [String]) {
        self.matches = matches
        self.ignores = ignores
    }
}

/// One entry of `rules.json`.
public struct Rule: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let severity: Severity
    public let match: RuleMatch
    public let message: String
    /// What happens, in plain words; the fallback when no translation carries one.
    public let consequence: String?
    /// User rules may switch a built-in rule off without deleting it.
    public let enabled: Bool?
    /// Documented behaviour; optional, so user rule files need not carry it.
    public let examples: RuleExamples?

    public init(
        id: String,
        title: String,
        severity: Severity,
        match: RuleMatch,
        message: String,
        consequence: String? = nil,
        enabled: Bool? = nil,
        examples: RuleExamples? = nil)
    {
        self.id = id
        self.title = title
        self.severity = severity
        self.match = match
        self.message = message
        self.consequence = consequence
        self.enabled = enabled
        self.examples = examples
    }

    public var isEnabled: Bool {
        enabled ?? true
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
