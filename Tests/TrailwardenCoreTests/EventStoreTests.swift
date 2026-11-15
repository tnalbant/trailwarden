// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class EventStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeEvent(
        id: String,
        sessionId: String = "session-1",
        kind: EventKind = .toolCall,
        ts: TimeInterval = 1_700_000_000,
        command: String = "ls -la",
        severity: Severity? = nil) -> Event
    {
        let risk = severity.map { [RiskHit(ruleId: "R1", severity: $0, message: "test")] } ?? []
        return Event(
            id: id,
            ts: Date(timeIntervalSince1970: ts),
            agent: .claudeCode,
            sessionId: sessionId,
            kind: kind,
            cwd: "/tmp/demo",
            gitBranch: "main",
            tool: "Bash",
            command: command,
            paths: ["/tmp/demo/a.txt"],
            preview: command,
            risk: risk,
            rawJSON: "{}")
    }

    func testInsertAndCount() throws {
        let store = try EventStore(inMemory: true)
        try store.insert(events: [
            makeEvent(id: "a"),
            makeEvent(id: "b", kind: .message)
        ])

        XCTAssertEqual(try store.eventCount(), 2)
    }

    func testInsertIsIdempotent() throws {
        let store = try EventStore(inMemory: true)
        let events = [makeEvent(id: "a"), makeEvent(id: "b")]

        try store.insert(events: events)
        try store.insert(events: events)

        XCTAssertEqual(try store.eventCount(), 2)
        let sessions = try store.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.eventCount, 2, "reprocessing must not double-count")
    }

    func testSessionAggregates() throws {
        let store = try EventStore(inMemory: true)
        try store.insert(events: [
            makeEvent(id: "a", ts: 1_700_000_000),
            makeEvent(id: "b", ts: 1_700_000_500, severity: .critical),
            makeEvent(id: "c", ts: 1_700_000_200, severity: .warn)
        ])

        let session = try XCTUnwrap(try store.sessions().first)
        XCTAssertEqual(session.id, "session-1")
        XCTAssertEqual(session.agent, .claudeCode)
        XCTAssertEqual(session.cwd, "/tmp/demo")
        XCTAssertEqual(session.gitBranch, "main")
        XCTAssertEqual(session.eventCount, 3)
        XCTAssertEqual(session.criticalCount, 1)
        XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(session.endedAt, Date(timeIntervalSince1970: 1_700_000_500))
    }

    func testFullTextSearchFindsCommand() throws {
        let store = try EventStore(inMemory: true)
        try store.insert(events: [
            makeEvent(id: "a", command: "rm -rf ~/.ssh"),
            makeEvent(id: "b", command: "swift test")
        ])

        let hits = try store.search("id_rsa")
        XCTAssertTrue(hits.isEmpty)

        let ssh = try store.search("ssh")
        XCTAssertEqual(ssh.map(\.id), ["a"])
        XCTAssertEqual(ssh.first?.command, "rm -rf ~/.ssh")
    }

    func testSearchSurvivesFTSOperatorsInUserText() throws {
        let store = try EventStore(inMemory: true)
        try store.insert(events: [makeEvent(id: "a", command: "echo \"quoted\" AND OR NOT")])

        XCTAssertNoThrow(try store.search("\"unbalanced"))
        XCTAssertNoThrow(try store.search("AND"))
        XCTAssertNoThrow(try store.search("*"))
    }

    func testReplacingAnEventUpdatesSearchIndex() throws {
        let store = try EventStore(inMemory: true)
        try store.insert(events: [makeEvent(id: "a", command: "first command")])
        try store.insert(events: [makeEvent(id: "a", command: "second command")])

        XCTAssertTrue(try store.search("first").isEmpty)
        XCTAssertEqual(try store.search("second").map(\.id), ["a"])
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testRawJSONIsCappedInTheStore() throws {
        let store = try EventStore(inMemory: true)
        let long = String(repeating: "x", count: 5000)
        let event = Event(
            id: "a",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .claudeCode,
            sessionId: "session-1",
            kind: .message,
            rawJSON: long)
        try store.insert(events: [event])

        let loaded = try XCTUnwrap(try store.events(ids: ["a"]).first)
        let raw = try XCTUnwrap(loaded.rawJSON)
        XCTAssertTrue(raw.hasSuffix("…[truncated]"))
        XCTAssertEqual(raw.count, EventStore.rawJSONLimit + "…[truncated]".count)
    }

    func testDatabaseFileHasOwnerOnlyPermissions() throws {
        let url = temporaryDirectory.appendingPathComponent("trailwarden.sqlite")
        _ = try EventStore(url: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testStoreReopensCleanly() throws {
        let url = temporaryDirectory.appendingPathComponent("trailwarden.sqlite")
        do {
            let store = try EventStore(url: url)
            try store.insert(events: [makeEvent(id: "a")])
        }
        let reopened = try EventStore(url: url)
        XCTAssertEqual(try reopened.eventCount(), 1)
    }

    func testFileSignatureRoundTrip() throws {
        let store = try EventStore(inMemory: true)
        XCTAssertNil(try store.fileSignature(path: "/tmp/a.jsonl"))

        try store.recordScan(
            path: "/tmp/a.jsonl",
            agent: .codex,
            size: 120,
            mtime: 1_700_000_000,
            sessionId: "session-9",
            events: 5,
            skipped: 1)

        let signature = try XCTUnwrap(try store.fileSignature(path: "/tmp/a.jsonl"))
        XCTAssertEqual(signature.size, 120)
        XCTAssertEqual(signature.mtime, 1_700_000_000)
        XCTAssertEqual(signature.sessionId, "session-9")
        XCTAssertEqual(signature.events, 5)
        XCTAssertEqual(signature.skipped, 1)
    }
}
