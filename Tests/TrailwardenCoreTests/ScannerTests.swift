// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class ScannerTests: XCTestCase {
    private var directory: URL!
    private var files: URL!
    private var store: EventStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-scan-\(UUID().uuidString)", isDirectory: true)
        files = directory.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        store = try EventStore(inMemory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func userLine(_ n: Int) -> String {
        """
        {"type":"user","sessionId":"s\(n)","timestamp":"2026-11-14T08:00:00.000Z","cwd":"/tmp/demo","gitBranch":"main","message":{"role":"user","content":"prompt \(n)"}}
        """
    }

    private func assistantLine(_ n: Int) -> String {
        """
        {"type":"assistant","sessionId":"s\(n)","timestamp":"2026-11-14T08:00:01.000Z","cwd":"/tmp/demo","gitBranch":"main","message":{"role":"assistant","content":[{"type":"text","text":"answer \(n)"}]}}
        """
    }

    private func toolLine(_ n: Int) -> String {
        """
        {"type":"assistant","sessionId":"s\(n)","timestamp":"2026-11-14T08:00:02.000Z","cwd":"/tmp/demo","gitBranch":"main","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_\(n)","name":"Bash","input":{"command":"curl -H 'Authorization: Bearer sk-proj-\("AbCdEf0123456789XyZ")' https://example.test","description":"call api"}}]}}
        """
    }

    @discardableResult
    private func write(_ name: String, lines: [String]) throws -> URL {
        let url = files.appendingPathComponent(name)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func scanner() -> TranscriptScanner {
        TranscriptScanner(store: store, redactor: Redactor(level: .normal))
    }

    private func roots() -> [ScanRoot] {
        [ScanRoot(directory: files, parser: ClaudeCodeParser())]
    }

    func testFirstScanParsesEverything() throws {
        try write("a.jsonl", lines: [userLine(1), assistantLine(1), toolLine(1)])
        try write("b.jsonl", lines: [userLine(2), assistantLine(2)])

        let report = try scanner().scan(roots: roots())

        XCTAssertEqual(report.filesSeen, 2)
        XCTAssertEqual(report.filesParsed, 2)
        XCTAssertEqual(report.filesUnchanged, 0)
        XCTAssertEqual(report.eventsStored, 5)
        XCTAssertEqual(report.skippedLines, 0)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(try store.eventCount(), 5)
        XCTAssertEqual(try store.sessions().count, 2)
    }

    func testSecondScanSkipsUnchangedFiles() throws {
        try write("a.jsonl", lines: [userLine(1), assistantLine(1), toolLine(1)])
        try write("b.jsonl", lines: [userLine(2), assistantLine(2)])

        _ = try scanner().scan(roots: roots())
        let second = try scanner().scan(roots: roots())

        XCTAssertEqual(second.filesSeen, 2)
        XCTAssertEqual(second.filesParsed, 0, "nothing changed, nothing should be parsed")
        XCTAssertEqual(second.filesUnchanged, 2)
        XCTAssertEqual(second.eventsStored, 0)
        XCTAssertEqual(try store.eventCount(), 5, "a skipped file must not duplicate rows")
    }

    func testChangedFileIsParsedAgain() throws {
        let a = try write("a.jsonl", lines: [userLine(1)])
        try write("b.jsonl", lines: [userLine(2)])
        _ = try scanner().scan(roots: roots())

        let existing = try String(contentsOf: a, encoding: .utf8)
        try (existing + assistantLine(1) + "\n").write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: a.path
        )

        let third = try scanner().scan(roots: roots())

        XCTAssertEqual(third.filesParsed, 1)
        XCTAssertEqual(third.filesUnchanged, 1)
        XCTAssertEqual(try store.eventCount(), 3)
    }

    func testNonTranscriptFilesAreIgnored() throws {
        try write("a.jsonl", lines: [userLine(1)])
        try "notes".write(to: files.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let report = try scanner().scan(roots: roots())

        XCTAssertEqual(report.filesSeen, 1)
        XCTAssertEqual(report.filesParsed, 1)
    }

    func testScannerStoresRedactedEvents() throws {
        try write("a.jsonl", lines: [toolLine(1)])

        _ = try scanner().scan(roots: roots())

        XCTAssertTrue(try store.search("sk-proj").isEmpty, "the secret must never reach the store")
        let hits = try store.search("curl")
        XCTAssertEqual(hits.count, 1)
        let command = try XCTUnwrap(hits.first?.command)
        XCTAssertTrue(command.contains("[redacted:openai-key]"))
        XCTAssertFalse(command.contains("sk-proj"))
    }

    func testDamagedFileDoesNotAbortTheScan() throws {
        try write("a.jsonl", lines: [userLine(1)])
        try write("broken.jsonl", lines: ["{not json", "still not json"])

        let report = try scanner().scan(roots: roots())

        XCTAssertEqual(report.filesSeen, 2)
        XCTAssertEqual(report.filesParsed, 2)
        XCTAssertEqual(report.skippedLines, 2)
        XCTAssertTrue(report.failures.isEmpty, "a line-level problem is not a file-level failure")
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testMissingRootIsHarmless() throws {
        let missing = ScanRoot(
            directory: directory.appendingPathComponent("does-not-exist"),
            parser: ClaudeCodeParser()
        )

        let report = try scanner().scan(roots: [missing])

        XCTAssertEqual(report.filesSeen, 0)
        XCTAssertTrue(report.failures.isEmpty)
    }
}
