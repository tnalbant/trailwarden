// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Allowances: the reader's scoped "this is expected" decisions. The scope is
/// stored in `scope` ('command', 'projectRule', 'pattern', 'everywhere'), `value`
/// (the command, project path or glob; empty for everywhere) and `project` (the
/// project path of a project allowance), so rows migrated from the old mutes
/// read as command allowances.
public extension EventStore {
    /// Stores an allowance and bumps the rules generation in the same
    /// transaction, so a running watcher never grades with half of the change.
    func addAllowance(_ allowance: Allowance) throws {
        let (kind, value, project) = Self.columns(for: allowance.scope)
        try database.transaction {
            // One row per (rule, scope, value): re-allowing replaces a migrated mute row too.
            let clear = try database
                .prepare("DELETE FROM allowances WHERE rule_id = ? AND scope = ? AND value = ?")
            try clear.bind([.text(allowance.ruleId), .text(kind), .text(value)])
            try clear.step()
            let statement = try database.prepare("""
            INSERT OR REPLACE INTO allowances (id, rule_id, scope, value, project, until, created)
            VALUES (?,?,?,?,?,?,?)
            """)
            try statement.bind([
                .text(allowance.id),
                .text(allowance.ruleId),
                .text(kind),
                .text(value),
                project.map { SQLValue.text($0) } ?? .null,
                allowance.until.map { SQLValue.double($0.timeIntervalSince1970) } ?? .null,
                .double(allowance.created.timeIntervalSince1970)
            ])
            try statement.step()
            try bumpRulesGeneration()
        }
    }

    func removeAllowance(id: String) throws {
        try database.transaction {
            let statement = try database.prepare("DELETE FROM allowances WHERE id = ?")
            try statement.bind([.text(id)])
            try statement.step()
            try bumpRulesGeneration()
        }
    }

    /// Every stored allowance, the ones that ran out included: the rule engine
    /// judges each at the time of the event it grades, so an expired allowance
    /// still covers what happened before its end.
    func gradingAllowances() throws -> [Allowance] {
        try allowances(now: .distantPast)
    }

    // MARK: - Rules generation

    /// The `meta` key of a counter that changes whenever the rules the index is
    /// graded with change: an allowance added or removed, a rule turned off or
    /// re-graded. A long-running watcher compares it to rebuild its engine.
    static let rulesGenerationKey = "rules_generation"

    func rulesGeneration() throws -> Int {
        try metaValue(Self.rulesGenerationKey).flatMap { Int($0) } ?? 0
    }

    func bumpRulesGeneration() throws {
        let statement = try database.prepare("""
        INSERT INTO meta (key, value) VALUES (?, '1')
        ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
        """)
        try statement.bind([.text(Self.rulesGenerationKey)])
        try statement.step()
    }

    /// The allowances that have not run out at `now`.
    func allowances(now: Date = Date()) throws -> [Allowance] {
        let statement = try database.prepare("""
        SELECT id, rule_id, scope, value, until, created FROM allowances
        WHERE until IS NULL OR until > ?
        ORDER BY created, id
        """)
        try statement.bind([.double(now.timeIntervalSince1970)])
        var result: [Allowance] = []
        while try statement.step() {
            guard let id = statement.text(0), let ruleId = statement.text(1),
                  let kind = statement.text(2),
                  let scope = Self.scope(kind: kind, value: statement.text(3) ?? "")
            else { continue }
            result.append(Allowance(
                id: id,
                ruleId: ruleId,
                scope: scope,
                until: statement.double(4).map { Date(timeIntervalSince1970: $0) },
                created: Date(timeIntervalSince1970: statement.double(5) ?? 0)))
        }
        return result
    }

    /// Drops allowances that have run out and returns how many were removed.
    /// Nothing calls it yet: expired rows are already ignored by `allowances(now:)`.
    @discardableResult
    func removeExpiredAllowances(now: Date = Date()) throws -> Int {
        let before = try allowanceRowCount()
        let statement = try database.prepare("DELETE FROM allowances WHERE until IS NOT NULL AND until <= ?")
        try statement.bind([.double(now.timeIntervalSince1970)])
        try statement.step()
        return try before - allowanceRowCount()
    }

    private func allowanceRowCount() throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM allowances")
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }

    private static func columns(for scope: AllowanceScope) -> (String, String, String?) {
        switch scope {
        case let .command(command): ("command", command, nil)
        case let .projectRule(project): ("projectRule", project, project)
        case let .pattern(glob): ("pattern", glob, nil)
        case .everywhere: ("everywhere", "", nil)
        }
    }

    private static func scope(kind: String, value: String) -> AllowanceScope? {
        switch kind {
        case "command": .command(value)
        case "projectRule": .projectRule(project: value)
        case "pattern": .pattern(glob: value)
        case "everywhere": .everywhere
        default: nil
        }
    }
}
