// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// Schema 9 adds reviews, allowances, file findings, archive copies and session titles.
final class SchemaNineTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-schema9-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Writes a schema 8 file: the nine-only tables and columns are gone, the mute is in place.
    private func makeSchemaEightFile(
        mute: (ruleId: String, target: String, until: Date)? = nil,
        prepare: (EventStore) throws -> Void = { _ in }) throws
        -> URL
    {
        let url = temporaryDirectory.appendingPathComponent("trailwarden.sqlite")
        let store = try EventStore(url: url)
        try prepare(store)
        _ = try store.prepareRowStatement("DELETE FROM meta WHERE key = 'inbox.firstLaunch'").step()
        for table in ["finding_reviews", "allowances", "file_findings", "archive_copies"] {
            _ = try store.prepareRowStatement("DROP TABLE \(table)").step()
        }
        _ = try store.prepareRowStatement("ALTER TABLE sessions DROP COLUMN title").step()
        _ = try store.prepareRowStatement("ALTER TABLE sessions DROP COLUMN title_source").step()
        _ = try store.prepareRowStatement("ALTER TABLE scanned_files DROP COLUMN missing_since").step()
        if let mute {
            let insert = try store.prepareRowStatement(
                "INSERT INTO mutes (rule_id, target, until) VALUES (?,?,?)")
            try insert.bind([
                .text(mute.ruleId),
                .text(mute.target),
                .double(mute.until.timeIntervalSince1970)
            ])
            _ = try insert.step()
        }
        _ = try store.prepareRowStatement("PRAGMA user_version = 8").step()
        return url
    }

    func testSchemaEightIndexGainsTheNineTables() throws {
        let url = try makeSchemaEightFile()

        let store = try EventStore(url: url)
        XCTAssertEqual(try store.schemaVersion(), 9)
        XCTAssertEqual(EventStore.schemaVersion, 9)
        for table in ["finding_reviews", "allowances", "file_findings", "archive_copies"] {
            let statement = try store.prepareRowStatement(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
            try statement.bind([.text(table)])
            XCTAssertTrue(try statement.step(), "\(table) exists")
        }
        XCTAssertTrue(try store.columnExists("title", in: "sessions"))
        XCTAssertTrue(try store.columnExists("title_source", in: "sessions"))
        XCTAssertTrue(try store.columnExists("missing_since", in: "scanned_files"))
    }

    func testMutesBecomeCommandAllowances() throws {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        let url = try makeSchemaEightFile(mute: ("R1", "rm -rf build", until))

        let store = try EventStore(url: url)
        let statement = try store.prepareRowStatement(
            "SELECT id, rule_id, scope, value, project, until FROM allowances")
        XCTAssertTrue(try statement.step())
        XCTAssertEqual(statement.text(0), "mute:R1|rm -rf build")
        XCTAssertEqual(statement.text(1), "R1")
        XCTAssertEqual(statement.text(2), "command")
        XCTAssertEqual(statement.text(3), "rm -rf build")
        XCTAssertNil(statement.text(4))
        XCTAssertEqual(statement.double(5), until.timeIntervalSince1970)
        XCTAssertFalse(try statement.step(), "exactly one allowance")

        let kept = try store.prepareRowStatement("SELECT COUNT(*) FROM mutes")
        XCTAssertTrue(try kept.step())
        XCTAssertEqual(kept.int(0), 1, "the mutes table stays for a downgrade")
    }

    func testReopeningDoesNotDuplicateAllowances() throws {
        let url = try makeSchemaEightFile(
            mute: ("R1", "rm -rf build", Date(timeIntervalSince1970: 1_800_000_000)))
        _ = try EventStore(url: url)
        let store = try EventStore(url: url)
        let count = try store.prepareRowStatement("SELECT COUNT(*) FROM allowances")
        XCTAssertTrue(try count.step())
        XCTAssertEqual(count.int(0), 1)
    }

    func testFindingKeys() {
        XCTAssertEqual(FindingKey.event("e1", rule: "R4"), "event:e1:R4")
        XCTAssertEqual(
            FindingKey.file(path: "~/.claude/settings.json", rule: "R29", digest: "ab12cd34ef56"),
            "file:~/.claude/settings.json:R29:ab12cd34ef56")
        XCTAssertEqual(FindingKey.ruleID(of: "event:e1:R4"), "R4")
        XCTAssertEqual(FindingKey.ruleID(of: "file:~/.claude/settings.json:R29:ab12cd34ef56"), "R29")
        XCTAssertEqual(FindingKey.ruleID(of: "event:a:b:c:R7"), "R7")
        XCTAssertEqual(FindingKey.ruleID(of: "file:~/odd:dir/x.json:R30:ab12cd34ef56"), "R30")
        XCTAssertNil(FindingKey.ruleID(of: "nonsense"))
    }

    func testReviewStateRawValues() {
        XCTAssertEqual(ReviewState.allCases.map(\.rawValue), ["new", "reviewed", "expected", "falsePositive"])
    }

    func testRefreshSessionKeepsTheTitle() throws {
        let store = try EventStore(url: temporaryDirectory.appendingPathComponent("t.sqlite"))
        let event = Event(
            id: "e1",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .claudeCode,
            sessionId: "s1",
            kind: .toolCall,
            tool: "Bash",
            command: "ls",
            preview: "ls")
        try store.insert(events: [event])
        _ = try store.prepareRowStatement(
            "UPDATE sessions SET title = 'T', title_source = 'summary' WHERE id = 's1'").step()
        try store.refreshSession("s1")
        let row = try store.prepareRowStatement("SELECT title, title_source FROM sessions WHERE id = 's1'")
        XCTAssertTrue(try row.step())
        XCTAssertEqual(row.text(0), "T")
        XCTAssertEqual(row.text(1), "summary")
    }

    // MARK: - Upgrade moment and sources gone before it

    func testUpgradeRecordsTheBacklogCutoff() throws {
        let url = try makeSchemaEightFile()
        let before = Date()
        let store = try EventStore(url: url)
        let stored = try XCTUnwrap(store.metaValue(Inbox.firstLaunchKey).flatMap(Double.init))
        XCTAssertGreaterThanOrEqual(stored, before.timeIntervalSince1970 - 1)
        XCTAssertLessThanOrEqual(stored, Date().timeIntervalSince1970 + 1)

        // Opening the inbox much later keeps the upgrade moment.
        _ = try Inbox.load(from: store, now: Date().addingTimeInterval(86400))
        XCTAssertEqual(try store.metaValue(Inbox.firstLaunchKey).flatMap(Double.init), stored)
    }

    func testNewIndexRecordsTheBacklogCutoffAtCreation() throws {
        let store = try EventStore(url: temporaryDirectory.appendingPathComponent("fresh.sqlite"))
        XCTAssertNotNil(try store.metaValue(Inbox.firstLaunchKey))
    }

    func testSourceGoneBeforeUpgradeIsMarkedAndTitled() throws {
        let gone = temporaryDirectory.appendingPathComponent("projects/gone.jsonl").path
        let kept = temporaryDirectory.appendingPathComponent("kept.jsonl")
        try "{}\n".write(to: kept, atomically: true, encoding: .utf8)
        let userLine = #"{"type":"user","sessionId":"s-gone","message":{"role":"user","content":"Fix the login page"}}"#
        let url = try makeSchemaEightFile { store in
            try store.insert(events: [
                Event(
                    id: "m1", ts: Date(timeIntervalSince1970: 1_700_000_000), agent: .claudeCode,
                    sessionId: "s-gone", kind: .message, preview: "Fix the login page", rawJSON: userLine),
                Event(
                    id: "m2", ts: Date(timeIntervalSince1970: 1_700_000_100), agent: .claudeCode,
                    sessionId: "s-kept", kind: .message, preview: "hi")
            ])
            for (path, session) in [(gone, "s-gone"), (kept.path, "s-kept")] {
                let insert = try store.prepareRowStatement("""
                INSERT INTO scanned_files (path, agent, size, mtime, session_id, events, skipped, scanned_at)
                VALUES (?, 'claude-code', 10, 0, ?, 1, 0, 0)
                """)
                try insert.bind([.text(path), .text(session)])
                _ = try insert.step()
            }
        }

        let store = try EventStore(url: url)

        let rows = try store.prepareRowStatement("SELECT path, missing_since FROM scanned_files")
        var remaining: [String: Double?] = [:]
        while try rows.step() {
            try remaining[XCTUnwrap(rows.text(0))] = rows.double(1)
        }
        XCTAssertEqual(Array(remaining.keys), [gone], "the existing file is forgotten so it is read again")
        XCTAssertNotNil(remaining[gone].flatMap(\.self), "the gone file is marked missing")
        XCTAssertEqual(try store.sessionsWithDeletedSources(), ["s-gone"])

        let title = try store
            .prepareRowStatement("SELECT title, title_source FROM sessions WHERE id = 's-gone'")
        XCTAssertTrue(try title.step())
        XCTAssertEqual(title.text(0), "Fix the login page")
        XCTAssertEqual(title.text(1), SessionTitle.Source.firstMessage.rawValue)
    }
}
