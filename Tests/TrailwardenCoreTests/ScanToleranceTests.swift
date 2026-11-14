// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

/// A corrupt transcript must never abort a scan or lose the good files next to it.
final class ScanToleranceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tw-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ body: String) throws {
        try body.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testBrokenFileDoesNotStopTheOthers() throws {
        let good = """
        {"type":"assistant","uuid":"a1","timestamp":"2026-11-14T09:00:00.000Z","sessionId":"s1","cwd":"/tmp/demo","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -la"}}]}}
        """
        try write("good.jsonl", good)
        try write("half-written.jsonl", #"{"type":"assistant","uuid":"a2","timestamp":"#)

        let store = try EventStore(inMemory: true)
        let scanner = TranscriptScanner(store: store)
        let report = try scanner.scan(roots: [ScanRoot(directory: root, parser: ClaudeCodeParser())])

        XCTAssertEqual(report.filesSeen, 2)
        XCTAssertEqual(report.eventsStored, 1, "the good file is still parsed")
        XCTAssertGreaterThanOrEqual(report.skippedLines, 1, "the truncated line is counted, not fatal")
        XCTAssertTrue(report.failures.isEmpty, "a half-written line is not a file failure")
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testEmptyAndMissingDirectoriesAreHarmless() throws {
        let store = try EventStore(inMemory: true)
        let scanner = TranscriptScanner(store: store)

        let missing = ScanRoot(
            directory: root.appendingPathComponent("nope", isDirectory: true),
            parser: ClaudeCodeParser()
        )
        let report = try scanner.scan(roots: [missing])
        XCTAssertEqual(report.filesSeen, 0)
        XCTAssertTrue(report.failures.isEmpty)
    }
}
