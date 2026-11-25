// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// The schema 9 migration step, called from `migrate()`. Later 0.3 work that
/// must happen once at the 8 to 9 upgrade belongs in this function.
extension EventStore {
    func migrateToNine() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS finding_reviews (
            finding_key TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            at REAL NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS allowances (
            id TEXT PRIMARY KEY,
            rule_id TEXT NOT NULL,
            scope TEXT NOT NULL,
            value TEXT NOT NULL,
            project TEXT,
            until REAL,
            created REAL NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS file_findings (
            finding_key TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            rule_id TEXT NOT NULL,
            severity TEXT NOT NULL,
            line INTEGER,
            preview TEXT NOT NULL,
            found_at REAL NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS archive_copies (
            source_path TEXT NOT NULL,
            version INTEGER NOT NULL,
            archive_path TEXT NOT NULL,
            session_id TEXT,
            agent TEXT NOT NULL,
            source_size INTEGER NOT NULL,
            prefix_digest TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (source_path, version)
        )
        """)
        if try !columnExists("title", in: "sessions") {
            try database.execute("ALTER TABLE sessions ADD COLUMN title TEXT")
        }
        if try !columnExists("title_source", in: "sessions") {
            try database.execute("ALTER TABLE sessions ADD COLUMN title_source TEXT")
        }
        if try !columnExists("missing_since", in: "scanned_files") {
            try database.execute("ALTER TABLE scanned_files ADD COLUMN missing_since REAL")
        }
        let now = Date()
        // The inbox's backlog cutoff is the upgrade (or the creation of a new
        // index), not the first time someone opens the inbox.
        let firstLaunch = try database.prepare("INSERT OR IGNORE INTO meta (key, value) VALUES (?, ?)")
        try firstLaunch.bind([.text(Inbox.firstLaunchKey), .text(String(now.timeIntervalSince1970))])
        try firstLaunch.step()
        // Sources already deleted before the upgrade cannot be reread: they are
        // marked missing (so their rows survive the reread below) and their
        // sessions get a first-message title from the events the index kept.
        try markSourcesGoneBeforeUpgrade(now: now)
        // Existing sessions have no title yet: every source is read once more.
        // Event ids are stable, so the reread replaces rows in place and keeps
        // review states, allowances and the titles of surviving events.
        try requestFullReread()
        // Mutes become command allowances. The mutes table stays, unread, so a
        // downgrade does not crash.
        try database.execute("""
        INSERT OR IGNORE INTO allowances (id, rule_id, scope, value, project, until, created)
        SELECT 'mute:' || rule_id || '|' || target, rule_id, 'command', target, NULL, until,
               CAST(strftime('%s', 'now') AS REAL)
        FROM mutes
        """)
    }

    /// Marks scanned files that no longer exist. A file on a volume that is not
    /// mounted is left alone: not knowing is not the same as deleted.
    private func markSourcesGoneBeforeUpgrade(now: Date) throws {
        let rows = try database.prepare("SELECT path, session_id, agent FROM scanned_files")
        var gone: [(path: String, session: String?, agent: String?)] = []
        while try rows.step() {
            guard let path = rows.text(0), !FileManager.default.fileExists(atPath: path),
                  Self.volumeIsMounted(for: path) else { continue }
            gone.append((path, rows.text(1), rows.text(2)))
        }
        let mark = try database.prepare("UPDATE scanned_files SET missing_since = ? WHERE path = ?")
        for row in gone {
            try mark.bind([.double(now.timeIntervalSince1970), .text(row.path)])
            try mark.step()
        }
        let claudeSessions = Set(gone.filter { $0.agent == Agent.claudeCode.rawValue }.compactMap(\.session))
        for session in try sessionsWithDeletedSources().intersection(claudeSessions) {
            if let title = try storedFirstMessageTitle(claudeSession: session) {
                try setSessionTitle(title, for: session)
            }
        }
    }

    private static func volumeIsMounted(for path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.first == "Volumes", parts.count > 1 else { return true }
        return FileManager.default.fileExists(atPath: "/Volumes/\(parts[1])")
    }

    /// The first thing the user typed in a Claude Code session, read back from
    /// the stored (already redacted) source lines of its message events. Only
    /// Claude Code keeps a line per message in a form this can read.
    private func storedFirstMessageTitle(claudeSession session: String) throws -> SessionTitle? {
        let statement = try database.prepare("""
        SELECT raw_json FROM events
        WHERE session_id = ? AND agent = ? AND kind = 'message' AND raw_json IS NOT NULL
        ORDER BY ts, id
        """)
        try statement.bind([.text(session), .text(Agent.claudeCode.rawValue)])
        while try statement.step() {
            guard let line = statement.text(0),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "user", object["isMeta"] as? Bool != true,
                  let message = object["message"] as? [String: Any],
                  let text = ClaudeCodeParser.userText(message["content"]),
                  let title = SessionTitle.fromFirstMessage(text)
            else { continue }
            return title
        }
        return nil
    }
}
