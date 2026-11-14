// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

public extension EventStore {
    /// Every stored event, without the raw transcript line. Re-running the rules
    /// over the index needs the command, the paths and the current hits only.
    func eventsForReevaluation() throws -> [Event] {
        let statement = try prepareRowStatement("""
        SELECT events.id, events.ts, events.agent, events.session_id, events.kind, events.cwd,
               events.git_branch, events.tool, events.command, events.paths, events.preview,
               events.risk, NULL AS raw_json
        FROM events
        ORDER BY events.ts DESC, events.id ASC
        """)
        var result: [Event] = []
        while try statement.step() {
            if let event = Self.event(from: statement) { result.append(event) }
        }
        return result
    }
}
