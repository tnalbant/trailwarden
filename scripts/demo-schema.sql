-- SPDX-License-Identifier: Apache-2.0
-- The index schema (v5), dumped from EventStore's own migration so a demo
-- database is exactly what the app creates. Regenerate when the schema changes.
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    agent TEXT NOT NULL,
    cwd TEXT,
    git_branch TEXT,
    started_at REAL NOT NULL,
    ended_at REAL NOT NULL,
    event_count INTEGER NOT NULL DEFAULT 0,
    critical_count INTEGER NOT NULL DEFAULT 0
);
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
CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_severity ON events(severity);
CREATE TABLE IF NOT EXISTS scanned_files (
    path TEXT PRIMARY KEY,
    agent TEXT NOT NULL,
    size INTEGER NOT NULL,
    mtime REAL NOT NULL,
    session_id TEXT,
    events INTEGER NOT NULL DEFAULT 0,
    skipped INTEGER NOT NULL DEFAULT 0,
    scanned_at REAL NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
    preview, command, tool,
    content = 'events', content_rowid = 'rowid', tokenize = 'unicode61'
);
CREATE TRIGGER IF NOT EXISTS events_ai AFTER INSERT ON events BEGIN
    INSERT INTO events_fts(rowid, preview, command, tool)
    VALUES (new.rowid, new.preview, new.command, new.tool);
END;
CREATE TRIGGER IF NOT EXISTS events_ad AFTER DELETE ON events BEGIN
    INSERT INTO events_fts(events_fts, rowid, preview, command, tool)
    VALUES ('delete', old.rowid, old.preview, old.command, old.tool);
END;
CREATE TRIGGER IF NOT EXISTS events_au AFTER UPDATE ON events BEGIN
    INSERT INTO events_fts(events_fts, rowid, preview, command, tool)
    VALUES ('delete', old.rowid, old.preview, old.command, old.tool);
    INSERT INTO events_fts(rowid, preview, command, tool)
    VALUES (new.rowid, new.preview, new.command, new.tool);
END;
CREATE TABLE IF NOT EXISTS mutes (
    rule_id TEXT NOT NULL,
    target TEXT NOT NULL,
    until REAL NOT NULL,
    PRIMARY KEY (rule_id, target)
);
PRAGMA user_version = 5;
