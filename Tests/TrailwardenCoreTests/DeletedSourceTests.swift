// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class DeletedSourceTests: XCTestCase {
    private var directory: URL!
    private var files: URL!
    private var store: EventStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailwarden-deleted-\(UUID().uuidString)", isDirectory: true)
        files = directory.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        store = try EventStore(inMemory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let line = """
    {"type":"user","sessionId":"s1","timestamp":"2026-11-14T08:00:00.000Z","cwd":"/tmp/demo","gitBranch":"main","message":{"role":"user","content":"prompt"}}
    """

    private var roots: [ScanRoot] {
        [ScanRoot(directory: files, parser: ClaudeCodeParser())]
    }

    private var scanner: TranscriptScanner {
        TranscriptScanner(store: store, redactor: Redactor(level: .normal))
    }

    @discardableResult
    private func writeTranscript() throws -> URL {
        let url = files.appendingPathComponent("s1.jsonl")
        try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func sourceDeleted() throws -> Bool? {
        try store.sessions().first { $0.id == "s1" }?.sourceDeleted
    }

    func testDeletedTranscriptIsMarked() throws {
        let url = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        XCTAssertEqual(try sourceDeleted(), false)

        try FileManager.default.removeItem(at: url)
        _ = try scanner.scan(roots: roots)

        XCTAssertEqual(try sourceDeleted(), true)
        XCTAssertEqual(try store.eventCount(), 1)
    }

    func testRestoredTranscriptIsUnmarked() throws {
        let url = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        try FileManager.default.removeItem(at: url)
        _ = try scanner.scan(roots: roots)
        XCTAssertEqual(try sourceDeleted(), true)

        try writeTranscript()
        _ = try scanner.scan(roots: roots)
        XCTAssertEqual(try sourceDeleted(), false)
    }

    func testLiveScanNeverMarks() throws {
        let url = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        try FileManager.default.removeItem(at: url)

        _ = scanner.scan(changed: [url], roots: roots)

        XCTAssertEqual(try sourceDeleted(), false)
    }

    func testMarkIsKeptAcrossScansAndFullReread() throws {
        let url = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        try FileManager.default.removeItem(at: url)
        _ = try scanner.scan(roots: roots)
        let first = try store.markMissingSources(under: [files], now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(first, 0, "an already-marked file is not marked again")

        try store.requestFullReread()
        _ = try scanner.scan(roots: roots)

        XCTAssertEqual(try sourceDeleted(), true, "a reread cannot make a vanished source look present")
    }

    func testFilesOutsideTheScannedRootsAreLeftAlone() throws {
        let url = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        try FileManager.default.removeItem(at: url)

        let other = directory.appendingPathComponent("other", isDirectory: true)
        let marked = try store.markMissingSources(under: [other], now: Date())

        XCTAssertEqual(marked, 0)
        XCTAssertEqual(try sourceDeleted(), false)
    }

    func testSessionWithoutFileRowsIsNeverMarked() throws {
        _ = try store.insert(events: [
            Event(
                id: "e1", ts: Date(timeIntervalSince1970: 1_700_000_000), agent: .cursor,
                sessionId: "s1", kind: .message, preview: "hi")
        ])
        _ = try store.markMissingSources(under: [files], now: Date())
        XCTAssertEqual(try sourceDeleted(), false)
    }

    func testMissingRootMarksNothing() throws {
        _ = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        try FileManager.default.removeItem(at: files)

        let marked = try store.markMissingSources(under: [files], now: Date())

        XCTAssertEqual(marked, 0)
        XCTAssertEqual(try sourceDeleted(), false)
    }

    func testReturnedFileIsReadAgainInTheSameScan() throws {
        let url = try writeTranscript()
        _ = try scanner.scan(roots: roots)
        try FileManager.default.removeItem(at: url)
        _ = try scanner.scan(roots: roots)
        try store.requestFullReread()

        try writeTranscript()
        let report = try scanner.scan(roots: roots)

        XCTAssertEqual(report.filesParsed, 1)
        XCTAssertEqual(try sourceDeleted(), false)
    }
}
