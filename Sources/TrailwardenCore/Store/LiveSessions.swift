// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

public extension EventStore {
    /// Sessions that wrote an event in the last `within` seconds — the ones an
    /// agent is probably still working in. Cheap on purpose: one grouped query.
    func activeSessionIDs(within seconds: TimeInterval = 120, now: Date = Date()) throws -> Set<String> {
        let cutoff = now.addingTimeInterval(-seconds)
        let statement = try prepareRowStatement("""
        SELECT DISTINCT session_id FROM events
        WHERE ts >= ? AND session_id IS NOT NULL AND session_id != ''
        """)
        try statement.bind([.double(cutoff.timeIntervalSince1970)])
        var ids: Set<String> = []
        while try statement.step() {
            if let id = statement.text(0) {
                ids.insert(id)
            }
        }
        return ids
    }
}
