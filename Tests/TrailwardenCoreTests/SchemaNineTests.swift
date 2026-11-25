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
    private func makeSchemaEightFile(mute: Mute? = nil) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("trailwarden.sqlite")
        let store = try EventStore(url: url)
        for table in ["finding_reviews", "allowances", "file_findings", "archive_copies"] {
            _ = try store.prepareRowStatement("DROP TABLE \(table)").step()
        }
        _ = try store.prepareRowStatement("ALTER TABLE sessions DROP COLUMN title").step()
        _ = try store.prepareRowStatement("ALTER TABLE sessions DROP COLUMN title_source").step()
        _ = try store.prepareRowStatement("ALTER TABLE scanned_files DROP COLUMN missing_since").step()
        if let mute {
            try store.addMute(mute)
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
        let url = try makeSchemaEightFile(mute: Mute(ruleId: "R1", target: "rm -rf build", until: until))

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
            mute: Mute(
                ruleId: "R1",
                target: "rm -rf build",
                until: Date(timeIntervalSince1970: 1_800_000_000)))
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
}
