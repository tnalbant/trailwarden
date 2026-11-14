// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class PruneTests: XCTestCase {
    private var store: EventStore!
    private let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!

    override func setUpWithError() throws {
        store = try EventStore(inMemory: true)
    }

    private func event(id: String, daysAgo: Double, session: String, preview: String) -> Event {
        Event(
            id: id,
            ts: now.addingTimeInterval(-daysAgo * 86_400),
            agent: .claudeCode,
            sessionId: session,
            kind: .toolCall,
            tool: "Bash",
            command: preview,
            paths: [],
            preview: preview,
            risk: [],
            rawJSON: nil
        )
    }

    func testPrunesOnlyTheOldEvents() throws {
        try store.insert(events: [
            event(id: "old1", daysAgo: 120, session: "cold", preview: "ancient secret"),
            event(id: "old2", daysAgo: 100, session: "cold", preview: "older still"),
            event(id: "new1", daysAgo: 10, session: "warm", preview: "recent work"),
        ])

        let report = try store.prune(eventsOlderThanDays: 90, now: now)

        XCTAssertEqual(report.removedEvents, 2)
        XCTAssertEqual(report.removedSessions, 1, "the session with nothing left is dropped")
        XCTAssertEqual(try store.events(matching: EventQuery()).map(\.id), ["new1"])
        XCTAssertEqual(try store.sessions().map(\.id), ["warm"])
    }

    func testPrunedTextLeavesTheSearchIndex() throws {
        try store.insert(events: [event(id: "old1", daysAgo: 200, session: "cold", preview: "ancient secret")])
        XCTAssertEqual(try store.events(matching: EventQuery(search: "ancient")).count, 1)

        try store.prune(eventsOlderThanDays: 90, now: now)

        XCTAssertEqual(try store.events(matching: EventQuery(search: "ancient")).count, 0)
    }

    func testPruneKeepsCountsConsistent() throws {
        try store.insert(events: [
            event(id: "old1", daysAgo: 120, session: "cold", preview: "a"),
            event(id: "new1", daysAgo: 1, session: "warm", preview: "b"),
            event(id: "new2", daysAgo: 2, session: "warm", preview: "c"),
        ])

        try store.prune(eventsOlderThanDays: 30, now: now)

        let warm = try XCTUnwrap(store.sessions().first { $0.id == "warm" })
        XCTAssertEqual(warm.eventCount, 2)
        XCTAssertEqual(try store.eventCount(), 2)
    }

    func testNothingToPruneIsFine() throws {
        try store.insert(events: [event(id: "new1", daysAgo: 1, session: "warm", preview: "b")])

        let report = try store.prune(eventsOlderThanDays: 90, now: now)

        XCTAssertEqual(report.removedEvents, 0)
        XCTAssertEqual(report.removedSessions, 0)
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testInvalidRetentionThrows() throws {
        XCTAssertThrowsError(try store.prune(eventsOlderThanDays: 0, now: now)) { error in
            XCTAssertEqual("\(error)", "retention must be at least 1 day, got 0")
        }
    }
}
