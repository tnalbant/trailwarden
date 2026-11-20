// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SQLite3
@testable import TrailwardenCore
import XCTest

/// Hermes keeps its history in SQLite, so the test builds a database with the
/// same shape and checks the mapping end to end.
final class HermesDatabaseParserTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hermes-\(UUID().uuidString).db")
        try makeDatabase()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeDatabase() throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }

        let schema = """
        CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT, cwd TEXT, model TEXT,
            started_at REAL NOT NULL, input_tokens INTEGER DEFAULT 0, output_tokens INTEGER DEFAULT 0);
        CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
            role TEXT NOT NULL, content TEXT, tool_name TEXT, tool_calls TEXT,
            timestamp REAL NOT NULL, active INTEGER DEFAULT 1);
        """
        XCTAssertEqual(sqlite3_exec(handle, schema, nil, nil, nil), SQLITE_OK)

        let start = Date().timeIntervalSince1970 - 600
        let inserts = """
        INSERT INTO sessions VALUES ('s1', 'cli', '/Users/demo/dev/aurora-api', 'gpt', \(start), 1200, 340);
        INSERT INTO messages (session_id, role, content, timestamp) VALUES
            ('s1', 'user', 'deploy the beta', \(start + 1));
        INSERT INTO messages (session_id, role, content, tool_calls, timestamp) VALUES
            ('s1', 'assistant', '', '[{"id":"c1","name":"terminal","arguments":"{\\"command\\":\\"rm -rf /tmp/x\\"}"}]', \(start + 2)),
            ('s1', 'assistant', '', '[{"id":"c2","name":"read_file","arguments":"{\\"path\\":\\"/Users/demo/dev/aurora-api/src/app.ts\\"}"}]', \(start + 3)),
            ('s1', 'assistant', 'done', NULL, \(start + 4));
        INSERT INTO messages (session_id, role, content, tool_name, timestamp) VALUES
            ('s1', 'tool', 'ok', 'terminal', \(start + 5));
        """
        XCTAssertEqual(sqlite3_exec(handle, inserts, nil, nil, nil), SQLITE_OK)
    }

    func testMapsTurnsCallsAndCounters() throws {
        let result = try HermesDatabaseParser().parse(database: url, since: nil)

        XCTAssertEqual(result.skippedLines, 0)
        XCTAssertEqual(result.events.count, 4, "user turn, two tool calls, one token counter")

        let shell = try XCTUnwrap(result.events.first { $0.tool == "terminal" })
        XCTAssertEqual(shell.agent, .hermes)
        XCTAssertEqual(shell.command, "rm -rf /tmp/x")
        XCTAssertEqual(shell.cwd, "/Users/demo/dev/aurora-api")
        XCTAssertEqual(shell.sessionId, "s1")

        let read = try XCTUnwrap(result.events.first { $0.tool == "read_file" })
        XCTAssertEqual(read.paths, ["/Users/demo/dev/aurora-api/src/app.ts"])

        let tokens = try XCTUnwrap(result.events.first { $0.kind == .tokenUsage })
        XCTAssertEqual(tokens.preview, "tokens: 1200 in / 340 out · gpt")
        XCTAssertEqual(tokens.usage, TokenCount(model: "gpt", input: 1200, output: 340))

        XCTAssertTrue(result.events.contains { $0.kind == .message && $0.preview == "deploy the beta" })
    }

    func testToolResultsAreNotEvents() throws {
        let result = try HermesDatabaseParser().parse(database: url, since: nil)
        XCTAssertFalse(result.events.contains { $0.preview == "ok" })
    }

    func testWatermarkSkipsOldRows() throws {
        let result = try HermesDatabaseParser().parse(database: url, since: Date())

        XCTAssertTrue(result.events.isEmpty, "nothing is newer than now")
    }

    func testMissingDatabaseIsNotAFailure() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nope.db")
        let result = try HermesDatabaseParser().parse(database: missing, since: nil)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testScannerReadsTheDatabaseIncrementally() throws {
        let store = try EventStore(inMemory: true)
        let scanner = TranscriptScanner(store: store)
        let source = DatabaseSource(database: url, parser: HermesDatabaseParser())

        let first = try scanner.scan(roots: [], databases: [source])
        XCTAssertEqual(first.eventsStored, 4)

        // The watermark is the newest stored timestamp and the query is inclusive,
        // so the boundary row is offered again — its id already exists and the
        // store ignores it. What must hold is that nothing is duplicated.
        _ = try scanner.scan(roots: [], databases: [source])
        XCTAssertEqual(try store.eventCount(matching: EventQuery(agents: [.hermes])), 4)
        XCTAssertEqual(
            try store.events(matching: EventQuery(agents: [.hermes])).map(\.id).count,
            try Set(store.events(matching: EventQuery(agents: [.hermes])).map(\.id)).count)
    }
}
