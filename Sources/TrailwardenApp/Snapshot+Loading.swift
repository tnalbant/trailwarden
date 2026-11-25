// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

extension Snapshot {
    /// The menu bar's state and the sessions active in the last two minutes,
    /// read on a connection of its own. Safe to call off the main actor.
    static func load(at url: URL) throws -> (snapshot: Snapshot, liveSessions: Set<String>) {
        let store = try EventStore(url: url)
        var snapshot = Snapshot()
        snapshot.sessions = try store.sessions()
        snapshot.totalEvents = try store.eventCount()

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let today = try store.events(matching: EventQuery(since: startOfDay, limit: 500))
        for event in today {
            switch event.activeRisk.map(\.severity).max() {
            case .critical: snapshot.criticalToday += 1
            case .warn: snapshot.warnToday += 1
            default: break
            }
        }
        snapshot.messagesToday = today.filter { $0.kind == .message }.count
        snapshot.recentActions = ActivityDigest.items(from: today, limit: 6)
        // Searched across the whole day, not across the six newest rows: a
        // critical from 09:00 is still today's critical at 21:00.
        let worstToday = today
            .filter { $0.activeRisk.contains { $0.severity == .critical } }
            .max { $0.ts < $1.ts }
        snapshot.latestCritical = worstToday.map { ActivityDigest.item(from: $0) }
        snapshot.unreviewedCritical = try Inbox.unreviewedCriticalCount(in: store)
        return try (snapshot, store.activeSessionIDs(within: 120))
    }
}
