// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// The schema 9 migration step, called from `migrate()`. Later 0.3 work that
/// must happen once at the 8 to 9 upgrade belongs in this function.
extension EventStore {
    func migrateToNine() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS finding_reviews (
            finding_key TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            at REAL NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS allowances (
            id TEXT PRIMARY KEY,
            rule_id TEXT NOT NULL,
            scope TEXT NOT NULL,
            value TEXT NOT NULL,
            project TEXT,
            until REAL,
            created REAL NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS file_findings (
            finding_key TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            rule_id TEXT NOT NULL,
            severity TEXT NOT NULL,
            line INTEGER,
            preview TEXT NOT NULL,
            found_at REAL NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS archive_copies (
            source_path TEXT NOT NULL,
            version INTEGER NOT NULL,
            archive_path TEXT NOT NULL,
            session_id TEXT,
            agent TEXT NOT NULL,
            source_size INTEGER NOT NULL,
            prefix_digest TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (source_path, version)
        )
        """)
        if try !columnExists("title", in: "sessions") {
            try database.execute("ALTER TABLE sessions ADD COLUMN title TEXT")
        }
        if try !columnExists("title_source", in: "sessions") {
            try database.execute("ALTER TABLE sessions ADD COLUMN title_source TEXT")
        }
        if try !columnExists("missing_since", in: "scanned_files") {
            try database.execute("ALTER TABLE scanned_files ADD COLUMN missing_since REAL")
        }
        // Existing sessions have no title yet: every source is read once more.
        // Event ids are stable, so the reread replaces rows in place and keeps
        // review states, allowances and the titles of surviving events.
        try requestFullReread()
        // Mutes become command allowances. The mutes table stays, unread, so a
        // downgrade does not crash.
        try database.execute("""
        INSERT OR IGNORE INTO allowances (id, rule_id, scope, value, project, until, created)
        SELECT 'mute:' || rule_id || '|' || target, rule_id, 'command', target, NULL, until,
               CAST(strftime('%s', 'now') AS REAL)
        FROM mutes
        """)
    }
}
