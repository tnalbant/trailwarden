// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// The token columns on `events`: what a token event read and wrote, split the
/// way providers bill it, and the model it was billed for.
extension EventStore {
    /// Old token rows carry only a preview line, and some will not come back
    /// under the same id (Codex now logs one row per change, Claude Code one
    /// per response). They are dropped and every source is read again: files by
    /// forgetting their signatures, databases by ignoring their watermark once.
    func forgetOldTokenEvents() throws {
        try requestFullReread()
        let sessions = try database.prepare(
            "SELECT DISTINCT session_id FROM events WHERE kind = 'token_usage'")
        var ids: [String] = []
        while try sessions.step() {
            if let id = sessions.text(0) {
                ids.append(id)
            }
        }
        try database.execute("DELETE FROM events WHERE kind = 'token_usage'")
        for id in ids {
            try refreshSession(id)
        }
    }

    /// The next scan reads every source in full: files by forgetting their
    /// signatures, databases by ignoring their watermark once.
    func requestFullReread() throws {
        try database.execute("DELETE FROM scanned_files")
        let reread = try database.prepare("INSERT OR IGNORE INTO rereads (agent) VALUES (?)")
        for agent in Agent.allCases {
            try reread.bind([.text(agent.rawValue)])
            try reread.step()
        }
    }

    static let usageColumnNames: [(name: String, type: String)] = [
        ("model", "TEXT"), ("tok_input", "INTEGER"), ("tok_output", "INTEGER"),
        ("tok_cache_read", "INTEGER"), ("tok_cache_write", "INTEGER"), ("tok_reasoning", "INTEGER")
    ]

    /// The token columns, in the order `event(from:)` reads them after `raw_json`.
    static let usageColumns = usageColumnNames.map { "events.\($0.name)" }.joined(separator: ", ")

    static func usageValues(_ usage: TokenCount?) -> [SQLValue] {
        guard let usage else { return Array(repeating: .null, count: usageColumnNames.count) }
        return [
            usage.model.map { SQLValue.text($0) } ?? .null,
            .int(usage.input), .int(usage.output), .int(usage.cacheRead), .int(usage.cacheWrite),
            .int(usage.reasoning)
        ]
    }

    /// Called after a database source was read in full.
    public func markReread(agent: Agent) throws {
        let statement = try prepareRowStatement("DELETE FROM rereads WHERE agent = ?")
        try statement.bind([.text(agent.rawValue)])
        try statement.step()
    }

    /// The token columns, when the query selected them and the row has any.
    static func usage(from statement: SQLiteStatement) -> TokenCount? {
        guard statement.columnCount >= 19,
              let input = statement.int(14), let output = statement.int(15) else { return nil }
        return TokenCount(
            model: statement.text(13),
            input: input,
            output: output,
            cacheRead: statement.int(16) ?? 0,
            cacheWrite: statement.int(17) ?? 0,
            reasoning: statement.int(18) ?? 0)
    }
}
