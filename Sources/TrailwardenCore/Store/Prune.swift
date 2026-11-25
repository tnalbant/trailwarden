// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

public struct PruneReport: Sendable, Equatable {
    public let removedEvents: Int
    public let removedSessions: Int
    public let cutoff: Date

    public init(removedEvents: Int, removedSessions: Int, cutoff: Date) {
        self.removedEvents = removedEvents
        self.removedSessions = removedSessions
        self.cutoff = cutoff
    }
}

public extension EventStore {
    /// Drops events older than the retention window. The FTS index follows through
    /// its triggers; sessions that end up empty are deleted. File signatures are
    /// kept on purpose — the next scan must not re-import what was just pruned.
    @discardableResult
    func prune(eventsOlderThanDays days: Int, now: Date = Date()) throws -> PruneReport {
        guard days > 0 else {
            throw PruneError.invalidRetention(days)
        }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)

        let sessionsBefore = try sessions().map(\.id)
        let countStatement = try prepareRowStatement("SELECT COUNT(*) FROM events WHERE ts < ?")
        try countStatement.bind([.double(cutoff.timeIntervalSince1970)])
        let removedEvents = try countStatement.step() ? (countStatement.int(0) ?? 0) : 0
        guard removedEvents > 0 else {
            return PruneReport(removedEvents: 0, removedSessions: 0, cutoff: cutoff)
        }

        let delete = try prepareRowStatement("DELETE FROM events WHERE ts < ?")
        try delete.bind([.double(cutoff.timeIntervalSince1970)])
        try delete.step()
        try removeOrphanEventReviews()

        // Sessions are derived, so rebuild the rows that lost events and drop the
        // ones with nothing left.
        try refreshSessions(ids: sessionsBefore)
        let empty = try prepareRowStatement("""
        DELETE FROM sessions
        WHERE id NOT IN (SELECT DISTINCT session_id FROM events)
        """)
        try empty.step()
        let removedSessions = try sessionsBefore.count - (sessions().count)

        return PruneReport(removedEvents: removedEvents, removedSessions: removedSessions, cutoff: cutoff)
    }
}

public enum PruneError: Error, CustomStringConvertible, Sendable {
    case invalidRetention(Int)

    public var description: String {
        switch self {
        case let .invalidRetention(days): "retention must be at least 1 day, got \(days)"
        }
    }
}
