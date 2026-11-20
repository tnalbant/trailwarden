// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Mutes and stored rule hits: the part of the store that changes when the
/// reader silences a finding or the rules themselves change.
public extension EventStore {
    // MARK: - Mutes

    /// Silences one `(rule, target)` pair until `mute.until`.
    func addMute(_ mute: Mute) throws {
        let statement = try database.prepare("""
        INSERT OR REPLACE INTO mutes (rule_id, target, until) VALUES (?,?,?)
        """)
        try statement.bind([
            .text(mute.ruleId),
            .text(mute.target),
            .double(mute.until.timeIntervalSince1970)
        ])
        try statement.step()
    }

    func removeMute(_ mute: Mute) throws {
        let statement = try database.prepare("DELETE FROM mutes WHERE rule_id = ? AND target = ?")
        try statement.bind([.text(mute.ruleId), .text(mute.target)])
        try statement.step()
    }

    func mutes(now: Date = Date()) throws -> [Mute] {
        let statement = try database.prepare("SELECT rule_id, target, until FROM mutes WHERE until > ?")
        try statement.bind([.double(now.timeIntervalSince1970)])
        var result: [Mute] = []
        while try statement.step() {
            guard let ruleId = statement.text(0), let target = statement.text(1) else { continue }
            result.append(
                Mute(
                    ruleId: ruleId,
                    target: target,
                    until: Date(timeIntervalSince1970: statement.double(2) ?? 0)))
        }
        return result
    }

    /// Rewrites the rule hits of the listed events and re-derives the session
    /// rows that count them. The rule set changed, so stored hits are stale.
    @discardableResult
    func replaceRisk(_ hitsByEventID: [String: [RiskHit]]) throws -> Int {
        guard !hitsByEventID.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        let ids = Array(hitsByEventID.keys)

        // In chunks: SQLite caps the number of `?` in one statement (999 on
        // older builds), and a rule change can touch tens of thousands of events.
        var sessions: Set<String> = []
        for start in stride(from: 0, to: ids.count, by: 500) {
            let chunk = ids[start ..< min(start + 500, ids.count)]
            let lookup = try prepareRowStatement(
                "SELECT session_id FROM events WHERE id IN (\(chunk.map { _ in "?" }.joined(separator: ",")))")
            try lookup.bind(chunk.map { SQLValue.text($0) })
            while try lookup.step() {
                if let session = lookup.text(0) {
                    sessions.insert(session)
                }
            }
        }

        try database.transaction {
            let update = try database.prepare(
                "UPDATE events SET risk = ?, severity = ?, severity_rank = ? WHERE id = ?")
            for (id, hits) in hitsByEventID {
                let risk = try String(decoding: encoder.encode(hits), as: UTF8.self)
                let worst = hits.map(\.severity).max()
                try update.bind([
                    .text(risk),
                    worst.map { SQLValue.text($0.rawValue) } ?? .null,
                    worst.map { SQLValue.int($0.rank) } ?? .null,
                    .text(id)
                ])
                try update.step()
            }
        }

        for session in sessions {
            try refreshSession(session)
        }
        return hitsByEventID.count
    }

    /// Drops mutes that have run out; called at the start of a scan.
    @discardableResult
    func removeExpiredMutes(now: Date = Date()) throws -> Int {
        let statement = try database.prepare("DELETE FROM mutes WHERE until <= ?")
        try statement.bind([.double(now.timeIntervalSince1970)])
        try statement.step()
        return try count("mutes")
    }

    private func count(_ table: String) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table)")
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }
}
