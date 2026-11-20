// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SQLite3
@testable import TrailwardenCore
import XCTest

/// A synthetic opencode database with the columns the real one has (only the
/// ones the parser reads), and messages shaped like real assistant turns.
final class OpencodeDatabaseParserTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-\(UUID().uuidString).db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let schema = """
        CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT NOT NULL, time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL, tokens_input INTEGER NOT NULL DEFAULT 0,
            tokens_output INTEGER NOT NULL DEFAULT 0, tokens_cache_read INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL,
            seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
        CREATE TABLE credential (id TEXT, secret TEXT);
        INSERT INTO credential VALUES ('c', 'never-read');
        INSERT INTO session_v2 VALUES ('ses_1', '/Users/demo/dev/aurora', 1800000000000, 1800000600000, 1200, 300, 800);
        """
        XCTAssertEqual(sqlite3_exec(handle, schema, nil, nil, nil), SQLITE_OK)
        let messages: [(String, String, Int, String)] = [
            ("msg_1", "user", 1_800_000_001_000, #"{"text":"fix the flaky test","time":{"created":1}}"#),
            ("msg_2", "assistant", 1_800_000_002_000, """
            {"content":[
              {"type":"reasoning","text":"thinking"},
              {"type":"text","text":"Running the tests."},
              {"type":"tool","id":"t1","name":"shell","state":{"status":"completed",
                "input":{"command":"git push --force origin main","workdir":"/Users/demo/dev/aurora"}}},
              {"type":"tool","id":"t2","name":"edit","state":{"input":{"file_path":"/Users/demo/dev/aurora/App.swift",
                "oldString":"a","newString":"b"}}},
              {"type":"tool","id":"t3","name":"grep","state":{"input":{"pattern":"rm -rf ~","path":"src"}}},
              {"type":"tool","id":"t4","name":"read","state":{"input":{"path":"/Users/demo/dev/aurora/.env"}}}
            ]}
            """),
            ("msg_3", "idle", 1_800_000_003_000, #"{"outcome":"done"}"#),
            ("msg_4", "assistant", 1_800_000_004_000, "not json")
        ]
        for (index, message) in messages.enumerated() {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(
                handle,
                "INSERT INTO session_message VALUES (?,?,?,?,?,?,?)",
                -1,
                &statement,
                nil)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, message.0, -1, transient)
            sqlite3_bind_text(statement, 2, "ses_1", -1, transient)
            sqlite3_bind_text(statement, 3, message.1, -1, transient)
            sqlite3_bind_int64(statement, 4, Int64(index))
            sqlite3_bind_int64(statement, 5, Int64(message.2))
            sqlite3_bind_int64(statement, 6, Int64(message.2))
            sqlite3_bind_text(statement, 7, message.3, -1, transient)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testMessagesToolsAndTokensAreRead() throws {
        let result = try OpencodeDatabaseParser().parse(database: url, since: nil)

        XCTAssertEqual(result.skippedLines, 1, "the broken JSON row is counted, not fatal")
        XCTAssertEqual(result.events.filter { $0.kind == .message }.map(\.preview), [
            "fix the flaky test", "Running the tests."
        ])
        let tools = result.events.filter { $0.kind == .toolCall }
        XCTAssertEqual(tools.map(\.tool), ["shell", "edit", "grep", "read"])
        XCTAssertEqual(tools[0].command, "git push --force origin main")
        XCTAssertEqual(tools[1].paths, ["/Users/demo/dev/aurora/App.swift"])
        XCTAssertNil(tools[2].command, "a grep pattern is not a command that ran")
        XCTAssertTrue(tools.allSatisfy { $0.cwd == "/Users/demo/dev/aurora" && $0.agent == .opencode })

        let tokens = try XCTUnwrap(result.events.first { $0.kind == .tokenUsage })
        XCTAssertEqual(tokens.preview, "tokens: 2000 in / 300 out (cache read 800)")
        XCTAssertEqual(tokens.usage, TokenCount(input: 1200, output: 300, cacheRead: 800))
    }

    func testRulesSeeTheShellCommandAndTheFiles() throws {
        let engine = try RuleEngine.builtIn()
        let tools = try OpencodeDatabaseParser().parse(database: url, since: nil).events
            .filter { $0.kind == .toolCall }
        XCTAssertEqual(tools.map { Set(engine.hits(for: $0).map(\.ruleId)) }, [["R5"], [], [], ["R11"]])
    }

    func testEventIDsAreStableAcrossReads() throws {
        let first = try OpencodeDatabaseParser().parse(database: url, since: nil).events.map(\.id)
        let second = try OpencodeDatabaseParser().parse(database: url, since: nil).events.map(\.id)
        XCTAssertEqual(first, second)
    }

    func testAWatermarkSkipsOldMessagesButKeepsTheRereadWindow() throws {
        let afterEverything = Date(timeIntervalSince1970: 1_800_000_010)
        let recent = try OpencodeDatabaseParser().parse(database: url, since: afterEverything).events
        XCTAssertFalse(recent.isEmpty, "a running turn is re-read inside the window")

        let muchLater = afterEverything.addingTimeInterval(OpencodeDatabaseParser.rereadWindow + 3600)
        XCTAssertTrue(try OpencodeDatabaseParser().parse(database: url, since: muchLater).events.isEmpty)
    }

    func testAMissingDatabaseIsNotAnError() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/opencode.db")
        XCTAssertTrue(try OpencodeDatabaseParser().parse(database: missing, since: nil).events.isEmpty)
    }
}
