// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SQLite3
@testable import TrailwardenCore
import XCTest

/// A synthetic `state.vscdb` with the one table the parser reads, shaped like
/// Cursor's: JSON values, some stored as BLOB and some as TEXT, `params` and
/// `result` as JSON strings inside the JSON. Other keys stand in for the data
/// that must never be read.
final class CursorDatabaseParserTests: XCTestCase {
    private var url: URL!
    private let composer = "c0ffee00-0000-4000-8000-000000000001"
    private let base = 1_800_000_000_000.0

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-\(UUID().uuidString).vscdb")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, """
        CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'never-read');
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        """, nil, nil, nil), SQLITE_OK)

        func iso(_ offset: Double) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: Date(timeIntervalSince1970: (base + offset) / 1000))
        }
        func tool(
            _ name: String,
            _ params: [String: Any],
            result: [String: Any]? = nil,
            status: String = "completed") -> [String: Any]
        {
            var data: [String: Any] = ["name": name, "status": status, "params": encode(params)]
            if let result {
                data["result"] = encode(result)
            }
            return data
        }
        let rows: [(String, [String: Any], Bool)] = [
            ("composerData:\(composer)", [
                "composerId": composer, "createdAt": base, "lastUpdatedAt": base + 9000, "name": "Notes",
                "modelConfig": ["modelName": "demo-model"]
            ], true),
            ("bubbleId:\(composer):u1", [
                "type": 1, "text": "make a notes folder", "createdAt": iso(1000),
                "workspaceUris": ["file:///Users/demo/dev/aurora"],
                "tokenCount": ["inputTokens": 0, "outputTokens": 0]
            ], false),
            (
                "bubbleId:\(composer):u1/s:0",
                ["type": 2, "text": "", "capabilityType": 30, "createdAt": iso(1500)],
                true),
            ("bubbleId:\(composer):u1/t:call-1", [
                "type": 2, "capabilityType": 15, "createdAt": iso(2000), "startedAtMs": base + 2000,
                "completedAtMs": base + 2500,
                "toolFormerData": tool(
                    "run_terminal_command_v2",
                    ["command": "rm -rf ~/Documents && echo gone", "cwd": ""],
                    result: ["output": "gone\n", "rejected": false]),
                "tokenCount": ["inputTokens": 900, "outputTokens": 40]
            ], true),
            ("bubbleId:\(composer):u1/t:call-2", [
                "type": 2, "createdAt": iso(3000),
                "toolFormerData": tool(
                    "edit_file_v2",
                    ["relativeWorkspacePath": "/Users/demo/.cursor/mcp.json"])
            ], false),
            ("bubbleId:\(composer):u1/t:call-3", [
                "type": 2, "createdAt": iso(4000),
                "toolFormerData": tool(
                    "read_file_v2",
                    ["targetFile": "/Users/demo/missing.md"],
                    status: "error")
            ], true),
            ("bubbleId:\(composer):u1/t:call-4", [
                "type": 2, "createdAt": iso(5000),
                "toolFormerData": tool("grep", ["pattern": "rm -rf /", "path": "/Users/demo/dev/aurora"])
            ], true),
            ("bubbleId:\(composer):u1/s:5", ["type": 2, "text": "Done.", "createdAt": iso(6000)], true),
            ("bubbleId:other-composer:x", ["type": 1, "text": "another chat", "createdAt": iso(1)], true),
            ("agentKv:blob:abc", ["prompt": "never read"], true)
        ]
        for (key, value, asBlob) in rows {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(handle, "INSERT INTO cursorDiskKV VALUES (?, ?)", -1, &statement, nil)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            let data = try JSONSerialization.data(withJSONObject: value)
            if asBlob {
                _ = data.withUnsafeBytes { sqlite3_bind_blob(
                    statement,
                    2,
                    $0.baseAddress,
                    Int32(data.count),
                    transient) }
            } else {
                sqlite3_bind_text(statement, 2, String(decoding: data, as: UTF8.self), -1, transient)
            }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func encode(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
    }

    func testChatMessagesToolsAndTokens() throws {
        let events = try CursorDatabaseParser().parse(database: url, since: nil).events
            .filter { $0.sessionId == composer }

        XCTAssertEqual(events.first?.kind, .sessionStart)
        XCTAssertEqual(events.first?.preview, "Notes (demo-model)")
        XCTAssertEqual(events.filter { $0.kind == .message }.map(\.preview), ["make a notes folder", "Done."])
        XCTAssertTrue(events.dropFirst().allSatisfy { $0.cwd == "/Users/demo/dev/aurora" })

        let calls = events.filter { $0.kind == .toolCall }
        XCTAssertEqual(calls.map(\.tool), ["run_terminal_command_v2", "edit_file_v2", "read_file_v2", "grep"])
        XCTAssertEqual(calls[0].command, "rm -rf ~/Documents && echo gone")
        XCTAssertEqual(calls[1].paths, ["/Users/demo/.cursor/mcp.json"])
        XCTAssertNil(calls[3].command, "a grep pattern is not a command")

        XCTAssertEqual(events.filter { $0.kind == .toolResult }.map(\.preview), ["gone\n", "error: "])
        XCTAssertEqual(events.filter { $0.kind == .tokenUsage }.map(\.preview), ["tokens: 900 in / 40 out"])
        XCTAssertTrue(events.allSatisfy { $0.agent == .cursor })
    }

    func testEveryChatIsReadAndNothingElse() throws {
        let events = try CursorDatabaseParser().parse(database: url, since: nil).events
        XCTAssertEqual(
            Set(events.map(\.sessionId)),
            [composer],
            "a bubble without its composer row is not a chat")
        XCTAssertFalse(events
            .contains { ($0.rawJSON ?? "").contains("never") || ($0.preview ?? "").contains("never") })
    }

    func testTheRulesSeeTheCommandAndTheFile() throws {
        let engine = try RuleEngine.builtIn()
        let calls = try CursorDatabaseParser().parse(database: url, since: nil).events
            .filter { $0.kind == .toolCall }
        XCTAssertEqual(calls.map { Set(engine.hits(for: $0).map(\.ruleId)) }, [["R1"], ["R15"], [], []])
    }

    func testIDsAreStableAndAWatermarkKeepsTheWindow() throws {
        let first = try CursorDatabaseParser().parse(database: url, since: nil).events.map(\.id)
        XCTAssertEqual(first, try CursorDatabaseParser().parse(database: url, since: nil).events.map(\.id))
        XCTAssertEqual(Set(first).count, first.count)

        let justAfter = Date(timeIntervalSince1970: (base + 10000) / 1000)
        XCTAssertFalse(try CursorDatabaseParser().parse(database: url, since: justAfter).events.isEmpty)
        let muchLater = justAfter.addingTimeInterval(CursorDatabaseParser.rereadWindow + 3600)
        XCTAssertTrue(try CursorDatabaseParser().parse(database: url, since: muchLater).events.isEmpty)
    }

    func testAMissingDatabaseOrTableIsNotAnError() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/state.vscdb")
        XCTAssertTrue(try CursorDatabaseParser().parse(database: missing, since: nil).events.isEmpty)

        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).vscdb")
        var handle: OpaquePointer?
        sqlite3_open(empty.path, &handle)
        sqlite3_exec(handle, "CREATE TABLE ItemTable (key TEXT, value BLOB)", nil, nil, nil)
        sqlite3_close(handle)
        defer { try? FileManager.default.removeItem(at: empty) }
        XCTAssertTrue(try CursorDatabaseParser().parse(database: empty, since: nil).events.isEmpty)
    }
}
