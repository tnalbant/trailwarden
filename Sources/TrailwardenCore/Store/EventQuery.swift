// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Filter used by `scan` and `export`.
public struct EventQuery: Sendable {
    public var since: Date?
    public var agents: Set<Agent>?
    public var minimumSeverity: Severity?
    /// Only events that carry at least one rule hit.
    public var onlyFindings: Bool
    public var limit: Int?

    public init(
        since: Date? = nil,
        agents: Set<Agent>? = nil,
        minimumSeverity: Severity? = nil,
        onlyFindings: Bool = false,
        limit: Int? = nil
    ) {
        self.since = since
        self.agents = agents
        self.minimumSeverity = minimumSeverity
        self.onlyFindings = onlyFindings
        self.limit = limit
    }
}

public extension EventStore {
    /// Events matching the query, newest first.
    func events(matching query: EventQuery) throws -> [Event] {
        var conditions: [String] = []
        var values: [SQLValue] = []

        if let since = query.since {
            conditions.append("ts >= ?")
            values.append(.double(since.timeIntervalSince1970))
        }
        if let agents = query.agents, !agents.isEmpty {
            let placeholders = agents.map { _ in "?" }.joined(separator: ",")
            conditions.append("agent IN (\(placeholders))")
            values.append(contentsOf: agents.map { SQLValue.text($0.rawValue) })
        }
        if let severity = query.minimumSeverity {
            conditions.append("severity_rank IS NOT NULL AND severity_rank >= ?")
            values.append(.int(severity.rank))
        }
        if query.onlyFindings {
            conditions.append("severity_rank IS NOT NULL")
        }

        var sql = """
        SELECT id, ts, agent, session_id, kind, cwd, git_branch, tool, command,
               paths, preview, risk, raw_json
        FROM events
        """
        if !conditions.isEmpty {
            sql += "\nWHERE " + conditions.joined(separator: " AND ")
        }
        sql += "\nORDER BY ts DESC, id ASC"
        if let limit = query.limit {
            sql += "\nLIMIT ?"
            values.append(.int(limit))
        }

        let statement = try prepareRowStatement(sql)
        try statement.bind(values)
        var result: [Event] = []
        while try statement.step() {
            if let event = Self.event(from: statement) { result.append(event) }
        }
        return result
    }

    func sessions(agents: Set<Agent>?) throws -> [SessionSummary] {
        let all = try sessions()
        guard let agents, !agents.isEmpty else { return all }
        return all.filter { agents.contains($0.agent) }
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
}
