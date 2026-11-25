// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Allowances: the reader's scoped "this is expected" decisions. The scope is
/// stored in `scope` ('command', 'projectRule', 'pattern', 'everywhere'), `value`
/// (the command, project path or glob; empty for everywhere) and `project` (the
/// project path of a project allowance), so rows migrated from the old mutes
/// read as command allowances.
public extension EventStore {
    func addAllowance(_ allowance: Allowance) throws {
        let statement = try database.prepare("""
        INSERT OR REPLACE INTO allowances (id, rule_id, scope, value, project, until, created)
        VALUES (?,?,?,?,?,?,?)
        """)
        let (kind, value, project) = Self.columns(for: allowance.scope)
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
    }

    func removeAllowance(id: String) throws {
        let statement = try database.prepare("DELETE FROM allowances WHERE id = ?")
        try statement.bind([.text(id)])
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

    /// Drops allowances that have run out; called at the start of a scan.
    /// Returns how many were removed.
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
