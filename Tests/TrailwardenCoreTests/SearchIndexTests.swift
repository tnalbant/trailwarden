// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// The live guard re-reads a transcript on every append, so the same events are
/// written again and again. The search index must follow each rewrite, not keep
/// a copy of every version.
final class SearchIndexTests: XCTestCase {
    private func event(_ preview: String) -> Event {
        Event(
            id: "e1",
            ts: Date(timeIntervalSince1970: 1_800_000_000),
            agent: .claudeCode,
            sessionId: "s1",
            kind: .toolCall,
            cwd: "/Users/demo/dev/app",
            tool: "Bash",
            command: preview,
            preview: preview)
    }

    private func indexRows(_ store: EventStore) throws -> Int {
        let statement = try store.prepareRowStatement("SELECT count(*) FROM events_fts_docsize")
        _ = try statement.step()
        return statement.int(0) ?? -1
    }

    func testRewritingAnEventKeepsOneSearchEntry() throws {
        let store = try EventStore(inMemory: true)
        for round in 0 ..< 5 {
            _ = try store.insert(events: [event("echo round\(round)")])
        }
        XCTAssertEqual(try store.eventCount(), 1)
        XCTAssertEqual(try indexRows(store), 1, "one row, one search entry")
        XCTAssertEqual(try store.events(matching: EventQuery(search: "round4")).count, 1)
        XCTAssertTrue(
            try store.events(matching: EventQuery(search: "round0")).isEmpty,
            "the text that was replaced is no longer found")
    }

    func testAFileIndexIsCreatedPrivateAndAtTheCurrentSchema() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let store = try EventStore(url: url)
        XCTAssertEqual(try store.schemaVersion(), EventStore.schemaVersion)
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            let mode = try FileManager.default.attributesOfItem(atPath: url.path + suffix)[.posixPermissions]
            XCTAssertEqual((mode as? NSNumber)?.intValue, 0o600, "index\(suffix) is private")
        }
    }
}
