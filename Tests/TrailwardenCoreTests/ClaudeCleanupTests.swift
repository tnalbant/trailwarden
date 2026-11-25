// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class ClaudeCleanupTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func settings(_ text: String) throws -> URL {
        let url = directory.appendingPathComponent("settings.json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testPeriodDefaultsToThirty() throws {
        let missing = directory.appendingPathComponent("none.json")
        XCTAssertEqual(ClaudeCleanup.period(settingsURL: missing), 30)
        XCTAssertEqual(try ClaudeCleanup.period(settingsURL: settings("{\"theme\":\"dark\"}")), 30)
        XCTAssertEqual(
            try ClaudeCleanup.period(settingsURL: settings("{\"cleanupPeriodDays\":\"abc\"}")), 30)
        XCTAssertEqual(try ClaudeCleanup.period(settingsURL: settings("{not json")), 30)
        XCTAssertEqual(try ClaudeCleanup.period(settingsURL: settings("{\"cleanupPeriodDays\":0}")), 30)
    }

    func testPeriodReadsTheSetting() throws {
        XCTAssertEqual(try ClaudeCleanup.period(settingsURL: settings("{\"cleanupPeriodDays\":14}")), 14)
    }

    private func record(_ store: EventStore, _ name: String, _ agent: Agent, daysOld: Double, now: Date)
        throws
    {
        try store.recordScan(
            path: "/tmp/\(name).jsonl",
            agent: agent,
            size: 10,
            mtime: now.timeIntervalSince1970 - daysOld * 86400,
            sessionId: name,
            events: 1,
            skipped: 0)
    }

    func testExpiringSoonCountsOldClaudeSessionsOnly() throws {
        let store = try EventStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try record(store, "old", .claudeCode, daysOld: 25, now: now)
        try record(store, "fresh", .claudeCode, daysOld: 5, now: now)
        try record(store, "codex", .codex, daysOld: 25, now: now)

        XCTAssertEqual(try ClaudeCleanup.expiringSoon(store: store, period: 30, now: now), 1)
    }

    func testExpiringSoonSkipsSessionsWhoseSourceIsGone() throws {
        let store = try EventStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try record(store, "old", .claudeCode, daysOld: 25, now: now)
        try store.database.execute("UPDATE scanned_files SET missing_since = 1")

        XCTAssertEqual(try ClaudeCleanup.expiringSoon(store: store, period: 30, now: now), 0)
    }

    func testNewestFileDecidesWhenASessionHasSeveral() throws {
        let store = try EventStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordScan(
            path: "/tmp/a.jsonl", agent: .claudeCode, size: 1,
            mtime: now.timeIntervalSince1970 - 26 * 86400, sessionId: "s", events: 1, skipped: 0)
        try store.recordScan(
            path: "/tmp/b.jsonl", agent: .claudeCode, size: 1,
            mtime: now.timeIntervalSince1970 - 2 * 86400, sessionId: "s", events: 1, skipped: 0)

        XCTAssertEqual(try ClaudeCleanup.expiringSoon(store: store, period: 30, now: now), 0)
    }

    func testInboxSnapshotCarriesTheCountOnlyWithASettingsURL() throws {
        let store = try EventStore(inMemory: true)
        let now = Date()
        try record(store, "old", .claudeCode, daysOld: 25, now: now)
        let url = try settings("{\"cleanupPeriodDays\":30}")

        XCTAssertEqual(try Inbox.load(from: store, now: now).expiringClaudeSessions, 0)
        XCTAssertEqual(
            try Inbox.load(from: store, now: now, claudeSettingsURL: url).expiringClaudeSessions,
            1)
    }
}
