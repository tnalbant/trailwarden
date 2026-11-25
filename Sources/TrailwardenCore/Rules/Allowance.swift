// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// How far an allowance reaches.
public enum AllowanceScope: Codable, Sendable, Hashable {
    /// This exact normalized command.
    case command(String)
    /// Everything the rule flags inside a project folder and its subfolders.
    case projectRule(project: String)
    /// Targets matching a glob (`*` stays in one path component, `**` crosses).
    case pattern(glob: String)
    /// Every hit of the rule.
    case everywhere
}

/// A reader's decision that a rule's hits in some situation are expected.
public struct Allowance: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let ruleId: String
    public let scope: AllowanceScope
    /// Nil means the allowance never expires.
    public let until: Date?
    public let created: Date

    public init(
        id: String? = nil,
        ruleId: String,
        scope: AllowanceScope,
        until: Date?,
        created: Date = Date())
    {
        let scope = Self.normalized(scope)
        self.id = id ?? Self.makeID(ruleId: ruleId, scope: scope)
        self.ruleId = ruleId
        self.scope = scope
        self.until = until
        self.created = created
    }

    /// A project path never ends in a slash (except the root itself).
    private static func normalized(_ scope: AllowanceScope) -> AllowanceScope {
        guard case let .projectRule(project) = scope else { return scope }
        var trimmed = project
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return .projectRule(project: trimmed)
    }

    /// Deterministic, so allowing the same thing twice replaces the first one.
    static func makeID(ruleId: String, scope: AllowanceScope) -> String {
        switch scope {
        case let .command(command): "\(ruleId)|command|\(command)"
        case let .projectRule(project): "\(ruleId)|projectRule|\(project)"
        case let .pattern(glob): "\(ruleId)|pattern|\(glob)"
        case .everywhere: "\(ruleId)|everywhere|"
        }
    }

    /// The same decision for a different scope: a new id, the same end and creation date.
    public func rescoped(to scope: AllowanceScope) -> Allowance {
        Allowance(ruleId: ruleId, scope: scope, until: until, created: created)
    }

    /// What the pattern editor starts with: the current command, glob or project path.
    public var patternPrefill: String {
        switch scope {
        case let .command(value): value
        case let .pattern(glob): glob
        case let .projectRule(project): project
        case .everywhere: ""
        }
    }

    public func isActive(at date: Date) -> Bool {
        until.map { $0 > date } ?? true
    }

    public func covers(ruleId: String, target: String, cwd: String?) -> Bool {
        guard ruleId == self.ruleId else { return false }
        switch scope {
        case let .command(command):
            return target == command
        case let .projectRule(project):
            guard let cwd else { return false }
            return project == "/" || cwd == project || cwd.hasPrefix(project + "/")
        case let .pattern(glob):
            guard let regex = Glob.regex(for: glob) else { return false }
            return Glob.matches(regex, target)
        case .everywhere:
            return true
        }
    }
}

/// The durations the reader can pick for an allowance.
public enum AllowanceDuration: CaseIterable, Sendable {
    case oneDay
    case thirtyDays
    case forever

    public func until(from date: Date) -> Date? {
        switch self {
        case .oneDay: date.addingTimeInterval(86400)
        case .thirtyDays: date.addingTimeInterval(30 * 86400)
        case .forever: nil
        }
    }
}
