// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// One project folder the agents worked in, derived from its sessions.
public struct ProjectSummary: Sendable, Identifiable, Equatable {
    public let cwd: String
    public let sessionCount: Int
    public let eventCount: Int
    public let lastActivity: Date

    public var id: String { cwd }

    public init(cwd: String, sessionCount: Int, eventCount: Int, lastActivity: Date) {
        self.cwd = cwd
        self.sessionCount = sessionCount
        self.eventCount = eventCount
        self.lastActivity = lastActivity
    }
}

/// Filter used by `scan`, `export` and the timeline.
public struct EventQuery: Sendable {
    public var since: Date?
    public var until: Date?
    public var agents: Set<Agent>?
    public var minimumSeverity: Severity?
    /// Only events that carry at least one rule hit.
    public var onlyFindings: Bool
    /// Exact working directories to look at.
    public var projects: [String]?
    public var sessionIDs: Set<String>?
    /// Full-text search over the preview, the command and the tool name.
    public var search: String?
    /// Event kinds to leave out — token counters and session markers are noise
    /// in a timeline of what the agent did.
    public var excludedKinds: Set<EventKind>?
    public var limit: Int?
    public var offset: Int?

    public init(
        since: Date? = nil,
        until: Date? = nil,
        agents: Set<Agent>? = nil,
        minimumSeverity: Severity? = nil,
        onlyFindings: Bool = false,
        projects: [String]? = nil,
        sessionIDs: Set<String>? = nil,
        search: String? = nil,
        excludedKinds: Set<EventKind>? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.since = since
        self.until = until
        self.agents = agents
        self.minimumSeverity = minimumSeverity
        self.onlyFindings = onlyFindings
        self.projects = projects
        self.sessionIDs = sessionIDs
        self.search = search
        self.excludedKinds = excludedKinds
        self.limit = limit
        self.offset = offset
    }

    /// The search text as an FTS5 phrase, so user input can never inject FTS
    /// syntax (a bare `rm -rf` would otherwise be parsed as a column filter).
    var ftsPhrase: String? {
        guard let search else { return nil }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

public extension EventStore {
    /// Events matching the query, newest first.
    func events(matching query: EventQuery) throws -> [Event] {
        var (sql, values) = try timelineSQL(query, columns: Self.eventColumns)
        sql += "\nORDER BY events.ts DESC, events.id ASC"
        if let limit = query.limit {
            sql += "\nLIMIT ?"
            values.append(.int(limit))
            if let offset = query.offset, offset > 0 {
                sql += " OFFSET ?"
                values.append(.int(offset))
            }
        }

        let statement = try prepareRowStatement(sql)
        try statement.bind(values)
        var result: [Event] = []
        while try statement.step() {
            if let event = Self.event(from: statement) { result.append(event) }
        }
        return result
    }

    /// How many events the query matches, ignoring `limit` and `offset`.
    func eventCount(matching query: EventQuery) throws -> Int {
        let (sql, values) = try timelineSQL(query, columns: "COUNT(*)")
        let statement = try prepareRowStatement(sql)
        try statement.bind(values)
        guard try statement.step() else { return 0 }
        return statement.int(0) ?? 0
    }

    func sessions(agents: Set<Agent>?) throws -> [SessionSummary] {
        let all = try sessions()
        guard let agents, !agents.isEmpty else { return all }
        return all.filter { agents.contains($0.agent) }
    }

    /// Projects ordered by their most recent activity.
    func projects() throws -> [ProjectSummary] {
        let statement = try prepareRowStatement("""
        SELECT cwd, COUNT(*) AS sessions, SUM(event_count) AS events, MAX(ended_at) AS last
        FROM sessions
        WHERE cwd IS NOT NULL AND cwd != ''
        GROUP BY cwd
        ORDER BY last DESC
        """)
        var result: [ProjectSummary] = []
        while try statement.step() {
            guard let cwd = statement.text(0) else { continue }
            result.append(
                ProjectSummary(
                    cwd: cwd,
                    sessionCount: statement.int(1) ?? 0,
                    eventCount: statement.int(2) ?? 0,
                    lastActivity: Date(timeIntervalSince1970: statement.double(3) ?? 0)
                )
            )
        }
        return result
    }

    /// Count of rule hits per rule id inside the query.
    func ruleHitCounts(matching query: EventQuery) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in try events(matching: query) {
            for hit in event.risk {
                counts[hit.ruleId, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - SQL

    private static let eventColumns = """
    events.id, events.ts, events.agent, events.session_id, events.kind, events.cwd,
    events.git_branch, events.tool, events.command, events.paths, events.preview,
    events.risk, events.raw_json
    """

    /// Builds the shared FROM/WHERE part so the list and the count cannot drift.
    private func timelineSQL(_ query: EventQuery, columns: String) throws -> (String, [SQLValue]) {
        var conditions: [String] = []
        var values: [SQLValue] = []

        if let since = query.since {
            conditions.append("events.ts >= ?")
            values.append(.double(since.timeIntervalSince1970))
        }
        if let until = query.until {
            conditions.append("events.ts <= ?")
            values.append(.double(until.timeIntervalSince1970))
        }
        if let agents = query.agents, !agents.isEmpty {
            let placeholders = agents.map { _ in "?" }.joined(separator: ",")
            conditions.append("events.agent IN (\(placeholders))")
            values.append(contentsOf: agents.sorted { $0.rawValue < $1.rawValue }.map { .text($0.rawValue) })
        }
        if let severity = query.minimumSeverity {
            conditions.append("events.severity_rank IS NOT NULL AND events.severity_rank >= ?")
            values.append(.int(severity.rank))
        }
        if query.onlyFindings {
            conditions.append("events.severity_rank IS NOT NULL")
        }
        if let projects = query.projects, !projects.isEmpty {
            let placeholders = projects.map { _ in "?" }.joined(separator: ",")
            conditions.append("events.cwd IN (\(placeholders))")
            values.append(contentsOf: projects.map { .text($0) })
        }
        if let sessionIDs = query.sessionIDs, !sessionIDs.isEmpty {
            let placeholders = sessionIDs.map { _ in "?" }.joined(separator: ",")
            conditions.append("events.session_id IN (\(placeholders))")
            values.append(contentsOf: sessionIDs.sorted().map { .text($0) })
        }

        if let excluded = query.excludedKinds, !excluded.isEmpty {
            let placeholders = excluded.map { _ in "?" }.joined(separator: ",")
            conditions.append("events.kind NOT IN (\(placeholders))")
            values.append(contentsOf: excluded.map { .text($0.rawValue) })
        }

        var from = "FROM events"
        if let phrase = query.ftsPhrase {
            from = "FROM events_fts JOIN events ON events.rowid = events_fts.rowid"
            conditions.insert("events_fts MATCH ?", at: 0)
            values.insert(.text(phrase), at: 0)
        }

        var sql = "SELECT \(columns) \(from)"
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        return (sql, values)
    }
}
