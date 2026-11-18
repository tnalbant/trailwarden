// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Aggregated view of one agent session, derived from its events.
public struct SessionSummary: Sendable, Identifiable, Equatable {
    public let id: String
    public let agent: Agent
    public let cwd: String?
    public let gitBranch: String?
    public let startedAt: Date
    public let endedAt: Date
    public let eventCount: Int
    public let criticalCount: Int
}

/// What the incremental scanner remembers about a file it already parsed.
public struct FileSignature: Sendable, Equatable {
    public let path: String
    public let size: Int
    /// Modification time in seconds since 1970.
    public let mtime: Double
    public let sessionId: String?
    public let events: Int
    public let skipped: Int
    public let scannedAt: Date
}

/// Local index of events. One SQLite file, no ORM, schema versioned through
/// `PRAGMA user_version`.
///
/// The class is intentionally not `Sendable`: a store is owned by one queue at a
/// time (the CLI, the menu-bar app, the MCP server each open their own).
public final class EventStore {
    private let database: SQLiteDatabase

    /// `TRAILWARDEN_DB=<path>` points the app, the CLI and the MCP server at
    /// another index — a demo, or a copy for a bug report — so trying something
    /// out never writes into the real one. An explicit `--db` still wins.
    public static var environmentOverride: URL? {
        guard let path = ProcessInfo.processInfo.environment["TRAILWARDEN_DB"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Location of the real store: `~/Library/Application Support/Trailwarden/`.
    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let directory = support.appendingPathComponent("Trailwarden", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return directory.appendingPathComponent("trailwarden.sqlite")
    }

    public convenience init(inMemory: Bool = true) throws {
        try self.init(database: SQLiteDatabase(path: ":memory:"))
    }

    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let database = try SQLiteDatabase(path: url.path)
        try self.init(database: database)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private init(database: SQLiteDatabase) throws {
        self.database = database
        try migrate()
    }

    // MARK: - Schema

    private func migrate() throws {
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("PRAGMA synchronous = NORMAL")
        try database.execute("""
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            agent TEXT NOT NULL,
            cwd TEXT,
            git_branch TEXT,
            started_at REAL NOT NULL,
            ended_at REAL NOT NULL,
            event_count INTEGER NOT NULL DEFAULT 0,
            critical_count INTEGER NOT NULL DEFAULT 0
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            agent TEXT NOT NULL,
            kind TEXT NOT NULL,
            ts REAL NOT NULL,
            cwd TEXT,
            git_branch TEXT,
            tool TEXT,
            command TEXT,
            paths TEXT NOT NULL,
            preview TEXT,
            risk TEXT NOT NULL,
            severity TEXT,
            severity_rank INTEGER,
            raw_json TEXT
        )
        """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_events_severity ON events(severity)")
        try database.execute("""
        CREATE TABLE IF NOT EXISTS scanned_files (
            path TEXT PRIMARY KEY,
            agent TEXT NOT NULL,
            size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            session_id TEXT,
            events INTEGER NOT NULL DEFAULT 0,
            skipped INTEGER NOT NULL DEFAULT 0,
            scanned_at REAL NOT NULL
        )
        """)

        // v1 kept the FTS index in its own table and deleted rows by id, which is
        // a full scan per event. v2 uses the external-content layout: the index is
        // maintained by triggers keyed on rowid, so a delete is a lookup.
        if try userVersion() < 2 {
            try database.execute("DROP TRIGGER IF EXISTS events_ai")
            try database.execute("DROP TRIGGER IF EXISTS events_ad")
            try database.execute("DROP TRIGGER IF EXISTS events_au")
            try database.execute("DROP TABLE IF EXISTS events_fts")
        }
        let rebuildIndex = try userVersion() < 2
        try database.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
            preview, command, tool,
            content = 'events', content_rowid = 'rowid', tokenize = 'unicode61'
        )
        """)
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS events_ai AFTER INSERT ON events BEGIN
            INSERT INTO events_fts(rowid, preview, command, tool)
            VALUES (new.rowid, new.preview, new.command, new.tool);
        END
        """)
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS events_ad AFTER DELETE ON events BEGIN
            INSERT INTO events_fts(events_fts, rowid, preview, command, tool)
            VALUES ('delete', old.rowid, old.preview, old.command, old.tool);
        END
        """)
        try database.execute("""
        CREATE TRIGGER IF NOT EXISTS events_au AFTER UPDATE ON events BEGIN
            INSERT INTO events_fts(events_fts, rowid, preview, command, tool)
            VALUES ('delete', old.rowid, old.preview, old.command, old.tool);
            INSERT INTO events_fts(rowid, preview, command, tool)
            VALUES (new.rowid, new.preview, new.command, new.tool);
        END
        """)
        // A freshly created external-content index starts empty while `events`
        // may already hold rows (an upgraded v1 file). Without a rebuild the
        // first UPDATE asks FTS to delete a row it never had: "malformed".
        if rebuildIndex {
            try database.execute("INSERT INTO events_fts(events_fts) VALUES('rebuild')")
        }
        try database.execute("""
        CREATE TABLE IF NOT EXISTS mutes (
            rule_id TEXT NOT NULL,
            target TEXT NOT NULL,
            until REAL NOT NULL,
            PRIMARY KEY (rule_id, target)
        )
        """)
        // v4 adds a numeric severity rank so `--severity warn` is a range scan
        // instead of a string comparison (alphabetically "critical" < "warn").
        if try userVersion() < 4, try !columnExists("severity_rank", in: "events") {
            try database.execute("ALTER TABLE events ADD COLUMN severity_rank INTEGER")
        }
        // v5: the parsers learned Codex code-mode and the redactor stopped masking
        // long paths as blobs. Forgetting the file signatures makes the next scan
        // read every transcript once more; events keep their ids, so the rewrite
        // replaces rows instead of adding to them.
        if try userVersion() < 5 {
            try database.execute("DELETE FROM scanned_files")
        }
        try database.execute("PRAGMA user_version = 5")
    }

    /// Row statements for the query layer; keeps the database handle private.
    func prepareRowStatement(_ sql: String) throws -> SQLiteStatement {
        try database.prepare(sql)
    }

    private func columnExists(_ column: String, in table: String) throws -> Bool {
        let statement = try database.prepare("PRAGMA table_info(\(table))")
        while try statement.step() {
            if statement.text(1) == column {
                return true
            }
        }
        return false
    }

    private func userVersion() throws -> Int {
        let statement = try database.prepare("PRAGMA user_version")
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }

    // MARK: - Writing

    private static let insertEventSQL = """
    INSERT OR REPLACE INTO events
        (id, session_id, agent, kind, ts, cwd, git_branch, tool, command, paths, preview, risk, severity, severity_rank, raw_json)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """

    /// Inserts or replaces events and refreshes the affected session rows.
    /// Re-inserting the same events leaves the store unchanged.
    /// Raw source lines are kept for the detail view, but only up to this many
    /// characters: storing every full transcript line again would duplicate the
    /// agent's own files (a 180 MB rollout produced a 121 MB index).
    static let rawJSONLimit = 2048

    private static func cappedRawJSON(_ raw: String?) -> String? {
        guard let raw else { return nil }
        guard raw.count > rawJSONLimit else { return raw }
        return String(raw.prefix(rawJSONLimit)) + "…[truncated]"
    }

    @discardableResult
    public func insert(events: [Event]) throws -> Int {
        guard !events.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        try database.transaction {
            let insert = try database.prepare(Self.insertEventSQL)
            for event in events {
                let paths = try String(decoding: encoder.encode(event.paths), as: UTF8.self)
                let risk = try String(decoding: encoder.encode(event.risk), as: UTF8.self)
                let severity = event.risk.map(\.severity).max()
                let values: [SQLValue] = [
                    .text(event.id),
                    .text(event.sessionId),
                    .text(event.agent.rawValue),
                    .text(event.kind.rawValue),
                    .double(event.ts.timeIntervalSince1970),
                    event.cwd.map { SQLValue.text($0) } ?? .null,
                    event.gitBranch.map { SQLValue.text($0) } ?? .null,
                    event.tool.map { SQLValue.text($0) } ?? .null,
                    event.command.map { SQLValue.text($0) } ?? .null,
                    .text(paths),
                    event.preview.map { SQLValue.text($0) } ?? .null,
                    .text(risk),
                    severity.map { SQLValue.text($0.rawValue) } ?? .null,
                    severity.map { SQLValue.int($0.rank) } ?? .null,
                    Self.cappedRawJSON(event.rawJSON).map { SQLValue.text($0) } ?? .null
                ]
                try insert.bind(values)
                // The FTS index is maintained by the events_ai / events_au
                // triggers, so this stays a single statement per event.
                try insert.step()
            }
        }

        for sessionID in Set(events.map(\.sessionId)) {
            try refreshSession(sessionID)
        }
        return events.count
    }

    /// Recomputes a session row from its events, so reprocessing a file can never
    /// double-count.
    private func refreshSession(_ sessionID: String) throws {
        let select = try database.prepare("""
        SELECT agent, cwd, git_branch, MIN(ts), MAX(ts), COUNT(*),
               SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END)
        FROM events WHERE session_id = ?
        """)
        try select.bind([.text(sessionID)])
        guard try select.step(), let agentRaw = select.text(0),
              let agent = Agent(rawValue: agentRaw) else { return }
        let started = select.double(3) ?? 0
        let ended = select.double(4) ?? started
        let count = select.int(5) ?? 0
        let critical = select.int(6) ?? 0

        let upsert = try database.prepare("""
        INSERT INTO sessions (id, agent, cwd, git_branch, started_at, ended_at, event_count, critical_count)
        VALUES (?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            agent = excluded.agent,
            cwd = COALESCE(sessions.cwd, excluded.cwd),
            git_branch = COALESCE(sessions.git_branch, excluded.git_branch),
            started_at = excluded.started_at,
            ended_at = excluded.ended_at,
            event_count = excluded.event_count,
            critical_count = excluded.critical_count
        """)
        try upsert.bind([
            .text(sessionID),
            .text(agent.rawValue),
            select.text(1).map { SQLValue.text($0) } ?? .null,
            select.text(2).map { SQLValue.text($0) } ?? .null,
            .double(started),
            .double(ended),
            .int(count),
            .int(critical)
        ])
        try upsert.step()
    }

    /// One event by id, for the MCP `get_event` tool.
    public func event(id: String) throws -> Event? {
        let statement = try prepareRowStatement("""
        SELECT events.id, events.ts, events.agent, events.session_id, events.kind, events.cwd,
               events.git_branch, events.tool, events.command, events.paths, events.preview,
               events.risk, events.raw_json
        FROM events WHERE events.id = ? LIMIT 1
        """)
        try statement.bind([.text(id)])
        guard try statement.step() else { return nil }
        return Self.event(from: statement)
    }

    /// The newest event stored for an agent — the watermark for a database source.
    public func latestTimestamp(agent: Agent) throws -> Date? {
        let statement = try prepareRowStatement(
            "SELECT MAX(ts) FROM events WHERE agent = ?")
        try statement.bind([.text(agent.rawValue)])
        guard try statement.step(), let value = statement.double(0) else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// Re-derives the given session rows; used after bulk rewrites and pruning.
    public func refreshSessions(ids: [String]) throws {
        for id in ids {
            try refreshSession(id)
        }
    }

    public func recordScan(
        path: String,
        agent: Agent,
        size: Int,
        mtime: Double,
        sessionId: String?,
        events: Int,
        skipped: Int) throws
    {
        let statement = try database.prepare("""
        INSERT OR REPLACE INTO scanned_files
            (path, agent, size, mtime, session_id, events, skipped, scanned_at)
        VALUES (?,?,?,?,?,?,?,?)
        """)
        try statement.bind([
            .text(path),
            .text(agent.rawValue),
            .int(size),
            .double(mtime),
            sessionId.map { SQLValue.text($0) } ?? .null,
            .int(events),
            .int(skipped),
            .double(Date().timeIntervalSince1970)
        ])
        try statement.step()
    }

    // MARK: - Diagnostics

    public func schemaVersion() throws -> Int {
        try userVersion()
    }

    public func integrityCheck() throws -> String {
        let statement = try database.prepare("PRAGMA integrity_check")
        guard try statement.step(), let value = statement.text(0) else { return "unknown" }
        return value
    }

    // MARK: - Mutes

    /// Silences one `(rule, target)` pair until `mute.until`.
    public func addMute(_ mute: Mute) throws {
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

    public func removeMute(_ mute: Mute) throws {
        let statement = try database.prepare("DELETE FROM mutes WHERE rule_id = ? AND target = ?")
        try statement.bind([.text(mute.ruleId), .text(mute.target)])
        try statement.step()
    }

    public func mutes(now: Date = Date()) throws -> [Mute] {
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
    public func replaceRisk(_ hitsByEventID: [String: [RiskHit]]) throws -> Int {
        guard !hitsByEventID.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        let ids = Array(hitsByEventID.keys)

        let lookup = try prepareRowStatement(
            "SELECT session_id FROM events WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))")
        try lookup.bind(ids.map { SQLValue.text($0) })
        var sessions: Set<String> = []
        while try lookup.step() {
            if let session = lookup.text(0) {
                sessions.insert(session)
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
    public func removeExpiredMutes(now: Date = Date()) throws -> Int {
        let statement = try database.prepare("DELETE FROM mutes WHERE until <= ?")
        try statement.bind([.double(now.timeIntervalSince1970)])
        try statement.step()
        return try count("mutes")
    }

    private func count(_ table: String) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table)")
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }

    // MARK: - Reading

    public func eventCount() throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM events")
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }

    public func sessions() throws -> [SessionSummary] {
        let statement = try database.prepare("""
        SELECT id, agent, cwd, git_branch, started_at, ended_at, event_count, critical_count
        FROM sessions ORDER BY started_at DESC
        """)
        var result: [SessionSummary] = []
        while try statement.step() {
            guard let id = statement.text(0),
                  let agentRaw = statement.text(1),
                  let agent = Agent(rawValue: agentRaw) else { continue }
            result.append(
                SessionSummary(
                    id: id,
                    agent: agent,
                    cwd: statement.text(2),
                    gitBranch: statement.text(3),
                    startedAt: Date(timeIntervalSince1970: statement.double(4) ?? 0),
                    endedAt: Date(timeIntervalSince1970: statement.double(5) ?? 0),
                    eventCount: statement.int(6) ?? 0,
                    criticalCount: statement.int(7) ?? 0))
        }
        return result
    }

    public func fileSignature(path: String) throws -> FileSignature? {
        let statement = try database.prepare("""
        SELECT path, size, mtime, session_id, events, skipped, scanned_at
        FROM scanned_files WHERE path = ?
        """)
        try statement.bind([.text(path)])
        guard try statement.step(), let storedPath = statement.text(0) else { return nil }
        return FileSignature(
            path: storedPath,
            size: statement.int(1) ?? 0,
            mtime: statement.double(2) ?? 0,
            sessionId: statement.text(3),
            events: statement.int(4) ?? 0,
            skipped: statement.int(5) ?? 0,
            scannedAt: Date(timeIntervalSince1970: statement.double(6) ?? 0))
    }

    /// Full-text search over preview, command and tool name. The query is wrapped
    /// as an FTS5 phrase, so user text can never inject FTS syntax.
    public func search(_ query: String, limit: Int = 50) throws -> [Event] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let phrase = "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""

        let statement = try database.prepare("""
        SELECT events.id
        FROM events_fts JOIN events ON events.rowid = events_fts.rowid
        WHERE events_fts MATCH ?
        ORDER BY events.ts DESC
        LIMIT ?
        """)
        try statement.bind([.text(phrase), .int(limit)])
        var ids: [String] = []
        while try statement.step() {
            if let id = statement.text(0) {
                ids.append(id)
            }
        }
        return try events(ids: ids)
    }

    public func events(ids: [String]) throws -> [Event] {
        guard !ids.isEmpty else { return [] }
        let statement = try database.prepare("""
        SELECT id, ts, agent, session_id, kind, cwd, git_branch, tool, command,
               paths, preview, risk, raw_json
        FROM events WHERE id = ?
        """)
        var result: [Event] = []
        for id in ids {
            try statement.bind([.text(id)])
            guard try statement.step() else { continue }
            if let event = Self.event(from: statement) {
                result.append(event)
            }
        }
        return result.sorted { $0.ts > $1.ts }
    }

    static func event(from statement: SQLiteStatement) -> Event? {
        guard
            let id = statement.text(0),
            let agentRaw = statement.text(2),
            let agent = Agent(rawValue: agentRaw),
            let sessionID = statement.text(3),
            let kindRaw = statement.text(4),
            let kind = EventKind(rawValue: kindRaw)
        else { return nil }

        let decoder = JSONDecoder()
        let paths = statement.text(9)
            .flatMap { try? decoder.decode([String].self, from: Data($0.utf8)) } ?? []
        let risk = statement.text(11)
            .flatMap { try? decoder.decode([RiskHit].self, from: Data($0.utf8)) } ?? []

        return Event(
            id: id,
            ts: Date(timeIntervalSince1970: statement.double(1) ?? 0),
            agent: agent,
            sessionId: sessionID,
            kind: kind,
            cwd: statement.text(5),
            gitBranch: statement.text(6),
            tool: statement.text(7),
            command: statement.text(8),
            paths: paths,
            preview: statement.text(10),
            risk: risk,
            rawJSON: statement.text(12))
    }
}
