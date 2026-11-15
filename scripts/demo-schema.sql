-- SPDX-License-Identifier: Apache-2.0
-- Minimal schema, enough for a demo database. The app migrates it on open.
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    agent TEXT NOT NULL,
    kind TEXT NOT NULL,
    ts REAL NOT NULL,
    cwd TEXT,
    git_branch TEXT,
    tool TEXT,
    command TEXT,
    paths TEXT NOT NULL,
    preview TEXT,
    risk TEXT NOT NULL,
    severity TEXT,
    severity_rank INTEGER,
    raw_json TEXT
);
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    agent TEXT NOT NULL,
    cwd TEXT,
    git_branch TEXT,
    started_at REAL NOT NULL,
    ended_at REAL,
    event_count INTEGER NOT NULL DEFAULT 0,
    critical_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS scanned_files (
    path TEXT PRIMARY KEY,
    agent TEXT NOT NULL,
    size INTEGER NOT NULL,
    mtime REAL NOT NULL,
    session_id TEXT,
    event_count INTEGER NOT NULL DEFAULT 0,
    skipped_lines INTEGER NOT NULL DEFAULT 0,
    scanned_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS mutes (
    rule_id TEXT NOT NULL,
    target TEXT NOT NULL,
    created_at REAL NOT NULL,
    until REAL NOT NULL,
    PRIMARY KEY (rule_id, target)
);
CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
    command, preview, tool, content='events', content_rowid='rowid', tokenize='porter unicode61'
);
CREATE TRIGGER IF NOT EXISTS events_ai AFTER INSERT ON events BEGIN
    INSERT INTO events_fts(rowid, command, preview, tool)
    VALUES (new.rowid, new.command, new.preview, new.tool);
END;
CREATE TRIGGER IF NOT EXISTS events_ad AFTER DELETE ON events BEGIN
    INSERT INTO events_fts(events_fts, rowid, command, preview, tool)
    VALUES ('delete', old.rowid, old.command, old.preview, old.tool);
END;
CREATE TRIGGER IF NOT EXISTS events_au AFTER UPDATE ON events BEGIN
    INSERT INTO events_fts(events_fts, rowid, command, preview, tool)
    VALUES ('delete', old.rowid, old.command, old.preview, old.tool);
    INSERT INTO events_fts(rowid, command, preview, tool)
    VALUES (new.rowid, new.command, new.preview, new.tool);
END;
