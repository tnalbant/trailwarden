// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// One thing waiting for the reader's review: a rule hit on an event, or a
/// secret found in a file.
public struct InboxFinding: Sendable, Identifiable {
    public enum Source: Sendable {
        case event(Event)
        case file(path: String, line: Int?, preview: String)
    }

    /// The finding key (`FindingKey`), which reviews and allowances use too.
    public let id: String
    public let ruleId: String
    public let severity: Severity
    public let at: Date
    public let source: Source

    public init(id: String, ruleId: String, severity: Severity, at: Date, source: Source) {
        self.id = id
        self.ruleId = ruleId
        self.severity = severity
        self.at = at
        self.source = source
    }
}

public struct InboxSnapshot: Sendable {
    /// Worst first, then newest first; capped by the `limit` given to `load`.
    public let unreviewed: [InboxFinding]
    /// Every unreviewed critical finding, however many `unreviewed` holds.
    public let unreviewedCritical: Int
    /// How many findings predate the first 0.3 launch; non-nil only while the
    /// reader has not yet chosen what to do with them.
    public let backlog: Int?
    /// Claude Code sessions its own cleanup will delete within a week.
    public let expiringClaudeSessions: Int

    public init(
        unreviewed: [InboxFinding],
        unreviewedCritical: Int,
        backlog: Int?,
        expiringClaudeSessions: Int = 0)
    {
        self.unreviewed = unreviewed
        self.unreviewedCritical = unreviewedCritical
        self.backlog = backlog
        self.expiringClaudeSessions = expiringClaudeSessions
    }
}

/// The findings that have not been looked at yet.
public enum Inbox {
    static let firstLaunchKey = "inbox.firstLaunch"
    static let backlogResolvedKey = "inbox.backlogResolved"

    public static func load(
        from store: EventStore,
        now: Date = Date(),
        limit: Int = 200,
        claudeSettingsURL: URL? = nil)
        throws -> InboxSnapshot
    {
        let firstLaunch = try firstLaunchDate(store, now: now)
        var candidates: [InboxFinding] = []

        // Only events with at least one hit still waiting are decoded: a long
        // history of reviewed findings costs a SQL filter, not a JSON decode each.
        for event in try store.eventsWithUnreviewedFindings() {
            for hit in event.activeRisk {
                candidates.append(InboxFinding(
                    id: FindingKey.event(event.id, rule: hit.ruleId),
                    ruleId: hit.ruleId,
                    severity: hit.severity,
                    at: event.ts,
                    source: .event(event)))
            }
        }
        // An allowance by pattern or everywhere also covers a file finding, matched
        // against its (home-shortened) path.
        let fileAllowances = try store.allowances(now: now).filter {
            switch $0.scope {
            case .pattern, .everywhere: true
            case .command, .projectRule: false
            }
        }
        candidates += try fileFindings(store).filter { finding in
            guard case let .file(path, _, _) = finding.source else { return true }
            return !fileAllowances.contains { $0.covers(ruleId: finding.ruleId, target: path, cwd: nil) }
        }

        let states = try store.reviewStates(for: candidates.map(\.id))
        let open = candidates
            .filter { (states[$0.id] ?? .new) == .new }
            .sorted {
                if $0.severity.rank != $1.severity.rank {
                    return $0.severity.rank > $1.severity.rank
                }
                if $0.at != $1.at {
                    return $0.at > $1.at
                }
                return $0.id < $1.id
            }

        var backlog: Int?
        if try store.metaValue(backlogResolvedKey) == nil {
            let older = open.filter { $0.at < firstLaunch }.count
            backlog = older > 0 ? older : nil
        }
        return InboxSnapshot(
            unreviewed: Array(open.prefix(limit)),
            unreviewedCritical: open.filter { $0.severity == .critical }.count,
            backlog: backlog,
            expiringClaudeSessions: claudeSettingsURL.map {
                (try? ClaudeCleanup.expiringSoon(
                    store: store, period: ClaudeCleanup.period(settingsURL: $0), now: now)) ?? 0
            } ?? 0)
    }

    /// How many unreviewed critical findings there are, counted in SQL: no
    /// event is decoded. Counts the same (event, hit) pairs and file findings
    /// as `load`.
    public static func unreviewedCriticalCount(in store: EventStore) throws -> Int {
        let decided = ReviewState.allCases.filter { $0 != .new }.map { "'\($0.rawValue)'" }
            .joined(separator: ",")
        let statement = try store.database.prepare("""
        SELECT COUNT(*) FROM (
            SELECT 'event:' || events.id || ':' || json_extract(hit.value, '$.ruleId') AS finding_key
            FROM events, json_each(events.risk) AS hit
            WHERE events.risk LIKE '%"critical"%'
              AND json_extract(hit.value, '$.severity') = 'critical'
              AND COALESCE(json_extract(hit.value, '$.allowed'), 0) = 0
            UNION
            SELECT finding_key FROM file_findings WHERE severity = 'critical'
        ) AS open
        WHERE NOT EXISTS (
            SELECT 1 FROM finding_reviews AS review
            WHERE review.finding_key = open.finding_key AND review.state IN (\(decided)))
        """)
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }

    /// The reader's one-time choice about findings from before the first 0.3
    /// launch: mark them all reviewed, or leave them in the inbox.
    public static func resolveBacklog(_ store: EventStore, markReviewed: Bool, now: Date = Date()) throws {
        if markReviewed {
            try store.markAllReviewed(foundBefore: firstLaunchDate(store, now: now), at: now)
        }
        try store.setMetaValue("1", for: backlogResolvedKey)
    }

    /// Recorded by the schema 9 migration (the upgrade moment, or the creation
    /// of a new index); written here only for an index that somehow lacks it.
    private static func firstLaunchDate(_ store: EventStore, now: Date) throws -> Date {
        if let stored = try store.metaValue(firstLaunchKey), let seconds = Double(stored) {
            return Date(timeIntervalSince1970: seconds)
        }
        try store.setMetaValue(String(now.timeIntervalSince1970), for: firstLaunchKey)
        return now
    }

    private static func fileFindings(_ store: EventStore) throws -> [InboxFinding] {
        let statement = try store.database.prepare("""
        SELECT finding_key, path, rule_id, severity, line, preview, found_at FROM file_findings
        """)
        var result: [InboxFinding] = []
        while try statement.step() {
            guard let key = statement.text(0), let path = statement.text(1),
                  let rule = statement.text(2), let raw = statement.text(3),
                  let severity = Severity(rawValue: raw)
            else { continue }
            result.append(InboxFinding(
                id: key,
                ruleId: rule,
                severity: severity,
                at: Date(timeIntervalSince1970: statement.double(6) ?? 0),
                source: .file(path: path, line: statement.int(4), preview: statement.text(5) ?? "")))
        }
        return result
    }
}
