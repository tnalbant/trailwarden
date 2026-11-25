// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// Claude Code deletes transcripts older than `cleanupPeriodDays`. This reads
/// that setting (never writing it) and counts the sessions about to expire.
public enum ClaudeCleanup {
    public static let defaultPeriod = 30

    /// `~/.claude/settings.json`; the file is only ever read.
    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// The configured period in days; 30 when the file or key is missing, or
    /// the value is not a positive whole number.
    public static func period(settingsURL: URL) -> Int {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = object["cleanupPeriodDays"] as? Int, days > 0
        else { return defaultPeriod }
        return days
    }

    /// Claude Code sessions whose transcript is still on disk and whose newest
    /// file is older than `now - (period - days)` days.
    public static func expiringSoon(
        store: EventStore,
        period: Int,
        now: Date,
        within days: Int = 7)
        throws -> Int
    {
        let cutoff = now.timeIntervalSince1970 - Double(period - days) * 86400
        let statement = try store.database.prepare("""
        SELECT COUNT(*) FROM (
            SELECT session_id FROM scanned_files
            WHERE agent = ? AND session_id IS NOT NULL
            GROUP BY session_id
            HAVING COUNT(missing_since) = 0 AND MAX(mtime) < ?
        )
        """)
        try statement.bind([.text(Agent.claudeCode.rawValue), .double(cutoff)])
        return try statement.step() ? (statement.int(0) ?? 0) : 0
    }
}
