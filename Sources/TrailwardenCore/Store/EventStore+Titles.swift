// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Session titles live on the `sessions` row. `refreshSession` leaves them alone.
extension EventStore {
    /// Stores a title. An agent-written title replaces anything; a first
    /// message only fills an empty title, so a later partial read of a database
    /// (whose "first" message is not the first) can never rename a session.
    public func setSessionTitle(_ title: SessionTitle, for sessionID: String) throws {
        let statement = try database.prepare(title.source == .summary
            ? "UPDATE sessions SET title = ?, title_source = ? WHERE id = ?"
            : "UPDATE sessions SET title = ?, title_source = ? WHERE id = ? AND title IS NULL")
        try statement.bind([.text(title.text), .text(title.source.rawValue), .text(sessionID)])
        try statement.step()
    }

    func setSessionTitles(_ titles: [String: SessionTitle]) throws {
        for (id, title) in titles {
            try setSessionTitle(title, for: id)
        }
    }
}
