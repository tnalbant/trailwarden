// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SQLite3
@testable import TrailwardenCore
import XCTest

// swiftformat:disable wrap wrapArguments
/// Fixture sources: Claude Code 2.0.0 (`summary` and `ai-title` records), Codex CLI 0.60.0,
/// Gemini CLI session JSON, Copilot CLI 1.0.0; everything else is hand-written and synthetic.
final class SessionTitleTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-title-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func fixture(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(path)")
    }

    private func write(_ name: String, _ lines: [String]) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func claudeUser(_ session: String, _ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"type":"user","sessionId":"\(session)","timestamp":"2026-11-25T08:00:00.000Z","cwd":"/tmp/demo","message":{"role":"user","content":"\(escaped)"}}
        """
    }

    // MARK: - Claude

    func testClaudeSummaryWins() throws {
        let result = try ClaudeCodeParser().parse(file: fixture("claude/titled.jsonl"))

        let title = try XCTUnwrap(result.titles["sess-title-1"])
        XCTAssertEqual(title.source, .summary)
        XCTAssertEqual(title.text, "Rename notes to archive", "the later record wins, and beats the first message")
        XCTAssertEqual(result.skippedLines, 0)
    }

    func testClaudeSummaryWithoutSessionIdAttachesToTheFileSession() throws {
        let url = try write("summary-only.jsonl", [
            #"{"type":"summary","summary":"Plan the release","leafUuid":"x"}"#,
            claudeUser("sess-s", "hello there")
        ])
        let title = try XCTUnwrap(ClaudeCodeParser().parse(file: url).titles["sess-s"])
        XCTAssertEqual(title, SessionTitle(text: "Plan the release", source: .summary))
    }

    func testFirstUserMessageFallback() throws {
        let claude = try ClaudeCodeParser().parse(file: fixture("claude/first-message.jsonl"))
        XCTAssertEqual(
            claude.titles["sess-title-2"],
            SessionTitle(text: "fix the flaky login test", source: .firstMessage),
            "meta, tool results and later prompts are skipped; the first line, whitespace collapsed")

        let codex = try CodexParser().parse(file: fixture(
            "codex/rollout-2026-11-25T09-00-00-7d3e9a41-0b2c-4f58-a6d1-3c5e8f1b2a90.jsonl"))
        XCTAssertEqual(
            codex.titles["7d3e9a41-0b2c-4f58-a6d1-3c5e8f1b2a90"],
            SessionTitle(text: "add a dark mode toggle", source: .firstMessage))

        let gemini = try GeminiCLIParser().parse(file: fixture("gemini/session-titled.json"))
        XCTAssertEqual(
            gemini.titles["gemini-title-session"],
            SessionTitle(text: "summarise the changelog", source: .firstMessage))

        let copilot = try CopilotParser().parse(file: fixture(
            "copilot-titled/9c2e4a10-0000-4000-8000-00000000beef/events.jsonl"))
        XCTAssertEqual(
            copilot.titles["9c2e4a10-0000-4000-8000-00000000beef"],
            SessionTitle(text: "write a README for the aurora project", source: .firstMessage))
    }

    func testDatabaseAgentsTitleFromTheFirstUserMessage() throws {
        // Hermes
        let hermes = temporaryDirectory.appendingPathComponent("hermes.db")
        try exec(hermes, """
        CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT, cwd TEXT, model TEXT,
            started_at REAL NOT NULL, input_tokens INTEGER DEFAULT 0, output_tokens INTEGER DEFAULT 0);
        CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
            role TEXT NOT NULL, content TEXT, tool_name TEXT, tool_calls TEXT,
            timestamp REAL NOT NULL, active INTEGER DEFAULT 1);
        INSERT INTO sessions VALUES ('h1', 'cli', '/tmp/h', 'm', 1800000000, 0, 0);
        INSERT INTO messages (session_id, role, content, timestamp) VALUES
            ('h1', 'user', 'deploy the beta', 1800000001), ('h1', 'user', 'and then rest', 1800000002);
        """)
        let hermesResult = try HermesDatabaseParser().parse(database: hermes, since: nil)
        XCTAssertEqual(hermesResult.titles["h1"], SessionTitle(text: "deploy the beta", source: .firstMessage))

        // opencode
        let opencode = temporaryDirectory.appendingPathComponent("opencode.db")
        try exec(opencode, """
        CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT NOT NULL, time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL, tokens_input INTEGER NOT NULL DEFAULT 0,
            tokens_output INTEGER NOT NULL DEFAULT 0, tokens_cache_read INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL,
            seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
        INSERT INTO session_v2 VALUES ('o1', '/tmp/o', 1800000000000, 1800000600000, 0, 0, 0);
        INSERT INTO session_message VALUES ('m1', 'o1', 'user', 0, 1800000001000, 1800000001000, '{"text":"fix the flaky test"}');
        INSERT INTO session_message VALUES ('m2', 'o1', 'user', 1, 1800000002000, 1800000002000, '{"text":"later"}');
        """)
        let opencodeResult = try OpencodeDatabaseParser().parse(database: opencode, since: nil)
        XCTAssertEqual(opencodeResult.titles["o1"], SessionTitle(text: "fix the flaky test", source: .firstMessage))

        // Cursor
        let cursor = temporaryDirectory.appendingPathComponent("cursor.vscdb")
        try exec(cursor, """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES ('composerData:c1', '{"createdAt":1800000000000,"lastUpdatedAt":1800000009000}');
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:b2', '{"type":1,"text":"second prompt","createdAt":"2027-01-15T08:00:05.000Z"}');
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:b1', '{"type":1,"text":"make a notes folder","createdAt":"2027-01-15T08:00:01.000Z"}');
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:b3', '{"type":2,"text":"assistant reply","createdAt":"2027-01-15T08:00:02.000Z"}');
        """)
        let cursorResult = try CursorDatabaseParser().parse(database: cursor, since: nil)
        XCTAssertEqual(cursorResult.titles["c1"], SessionTitle(text: "make a notes folder", source: .firstMessage))
    }

    private func exec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
    }

    // MARK: - Shaping

    func testTitleIsTrimmedAndRedacted() throws {
        // Built at runtime: a literal secret-shaped string would trip the secret scanner.
        let token = "sk-" + "proj-" + String(repeating: "Ab3dE9", count: 6)
        let redacted = try XCTUnwrap(SessionTitle.fromFirstMessage("use \(token) for the deploy"))
        XCTAssertFalse(redacted.text.contains(token))
        XCTAssertTrue(redacted.text.hasSuffix("for the deploy"))

        let long = Array(repeating: "wordy", count: 40).joined(separator: " ")
        XCTAssertEqual(long.count, 239)
        let cut = try XCTUnwrap(SessionTitle.fromFirstMessage(long))
        XCTAssertLessThanOrEqual(cut.text.count, 61)
        XCTAssertTrue(cut.text.hasSuffix("…"))
        XCTAssertFalse(cut.text.dropLast().hasSuffix(" "))
        XCTAssertTrue(cut.text.dropLast().split(separator: " ").allSatisfy { $0 == "wordy" }, "cut on a word")

        XCTAssertEqual(SessionTitle.fromFirstMessage("short one")?.text, "short one")
    }

    func testEmptySessionHasNoTitle() throws {
        XCTAssertNil(SessionTitle.fromFirstMessage(""))
        XCTAssertNil(SessionTitle.fromFirstMessage("  \n \t\n"))
        XCTAssertNil(SessionTitle.fromFirstMessage("<system-reminder>be brief</system-reminder>"))

        let url = try write("empty.jsonl", [
            #"{"type":"assistant","sessionId":"e1","timestamp":"2026-11-25T08:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}"#
        ])
        XCTAssertTrue(try ClaudeCodeParser().parse(file: url).titles.isEmpty)

        let store = try EventStore(inMemory: true)
        _ = try store.insert(events: ClaudeCodeParser().parse(file: url).events)
        XCTAssertNil(try store.sessions().first?.title)
    }

    // MARK: - Store

    func testSetSessionTitleNeverDowngradesASummary() throws {
        let store = try EventStore(inMemory: true)
        let result = try ClaudeCodeParser().parse(file: fixture("claude/first-message.jsonl"))
        _ = try store.insert(events: result.events)

        try store.setSessionTitle(SessionTitle(text: "first", source: .firstMessage), for: "sess-title-2")
        XCTAssertEqual(try store.sessions().first?.title, "first")
        try store.setSessionTitle(SessionTitle(text: "named", source: .summary), for: "sess-title-2")
        XCTAssertEqual(try store.sessions().first?.title, "named")
        try store.setSessionTitle(
            SessionTitle(text: "other first", source: .firstMessage), for: "sess-title-2")
        XCTAssertEqual(try store.sessions().first?.title, "named")
    }

    func testTitleSurvivesRefreshAndRescan() throws {
        let store = try EventStore(inMemory: true)
        let directory = temporaryDirectory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture("claude/titled.jsonl"), to: directory.appendingPathComponent("titled.jsonl"))
        let roots = [ScanRoot(directory: directory, parser: ClaudeCodeParser())]

        _ = try TranscriptScanner(store: store).scan(roots: roots)
        XCTAssertEqual(try store.sessions().first?.title, "Rename notes to archive")

        try store.refreshSession("sess-title-1")
        XCTAssertEqual(try store.sessions().first?.title, "Rename notes to archive")

        try store.requestFullReread()
        let again = try TranscriptScanner(store: store).scan(roots: roots)
        XCTAssertEqual(again.filesParsed, 1, "the file was really read again")
        XCTAssertEqual(try store.sessions().count, 1)
        XCTAssertEqual(try store.sessions().first?.title, "Rename notes to archive")
    }

    func testV9MigrationForcesOneRereadSoOldSessionsGetTitles() throws {
        let url = temporaryDirectory.appendingPathComponent("old.sqlite")
        let directory = temporaryDirectory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture("claude/titled.jsonl"), to: directory.appendingPathComponent("titled.jsonl"))
        let roots = [ScanRoot(directory: directory, parser: ClaudeCodeParser())]

        // A schema 8 index that already knows the file, with no titles.
        let old = try EventStore(url: url)
        _ = try TranscriptScanner(store: old).scan(roots: roots)
        _ = try old.prepareRowStatement("UPDATE sessions SET title = NULL, title_source = NULL").step()
        _ = try old.prepareRowStatement("PRAGMA user_version = 8").step()

        let upgraded = try EventStore(url: url)
        XCTAssertNil(try upgraded.sessions().first?.title)
        let report = try TranscriptScanner(store: upgraded).scan(roots: roots)
        XCTAssertEqual(report.filesParsed, 1, "the signature was forgotten")
        XCTAssertEqual(try upgraded.sessions().first?.title, "Rename notes to archive")
        XCTAssertEqual(try upgraded.sessions().count, 1)
    }
}
