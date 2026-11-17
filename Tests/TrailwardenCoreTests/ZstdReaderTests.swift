// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// The `.zst` fixtures are the synthetic Codex rollout and generated filler,
/// compressed with the reference `zstd` tool; none of them holds real data.
final class ZstdReaderTests: XCTestCase {
    private let rolloutName = "rollout-2026-11-14T09-00-00-3f2a1c8e-7b4d-4a11-9c2e-1f0b6d5a8e33.jsonl"

    private func fixture(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(path)")
    }

    private func lines(of url: URL) throws -> [String] {
        var result: [String] = []
        try JSONLReader.forEachLine(at: url) { _, line in result.append(line) }
        return result
    }

    func testCompressedRolloutGivesTheSameLinesAsThePlainOne() throws {
        let plain = try lines(of: fixture("codex/\(rolloutName)"))
        let compressed = try lines(of: fixture("zstd/\(rolloutName).zst"))
        XCTAssertFalse(plain.isEmpty)
        XCTAssertEqual(compressed, plain)
    }

    func testCompressedRolloutGivesTheSameEventsAndIDs() throws {
        let parser = CodexParser()
        let plain = try parser.parse(file: fixture("codex/\(rolloutName)"))
        let compressed = try parser.parse(file: fixture("zstd/\(rolloutName).zst"))
        XCTAssertEqual(compressed.skippedLines, plain.skippedLines)
        XCTAssertEqual(compressed.events.map(\.kind), plain.events.map(\.kind))
        XCTAssertEqual(compressed.events.map(\.command), plain.events.map(\.command))
        XCTAssertEqual(
            Set(compressed.events.map(\.sessionId)),
            ["3f2a1c8e-7b4d-4a11-9c2e-1f0b6d5a8e33"])
    }

    func testIDsSurviveCodexCompressingAnIndexedFile() {
        // Same folder, same name, once plain and once compressed: the ids must
        // match, or a rollout compressed after indexing would be stored twice.
        let plain = URL(fileURLWithPath: "/demo/sessions/2026/11/14/\(rolloutName)")
        let compressed = plain.appendingPathExtension("zst")
        XCTAssertEqual(CodexParser.logicalPath(of: compressed), plain.path)
        XCTAssertEqual(CodexParser.sessionID(from: compressed), CodexParser.sessionID(from: plain))
    }

    func testCodexAcceptsOnlyItsOwnFiles() {
        let parser = CodexParser()
        XCTAssertTrue(parser.accepts(URL(fileURLWithPath: "/x/rollout.jsonl")))
        XCTAssertTrue(parser.accepts(URL(fileURLWithPath: "/x/rollout.jsonl.zst")))
        XCTAssertFalse(parser.accepts(URL(fileURLWithPath: "/x/archive.tar.zst")))
        XCTAssertFalse(parser.accepts(URL(fileURLWithPath: "/x/notes.txt")))
        XCTAssertFalse(ClaudeCodeParser().accepts(URL(fileURLWithPath: "/x/rollout.jsonl.zst")))
    }

    func testALargeFileIsStreamedAcrossManyChunks() throws {
        // 3.6 MB once decoded: several reader chunks and decoder buffers.
        var count = 0
        var last = ""
        try JSONLReader.forEachLine(at: fixture("zstd/large.jsonl.zst")) { number, line in
            count = number
            last = line
        }
        XCTAssertEqual(count, 60000)
        XCTAssertTrue(last.hasPrefix(#"{"n":59999,"#))
    }

    func testALineLongerThanSeveralChunksStaysOneLine() throws {
        // Codex writes multi-megabyte lines; they span many reads.
        let long = String(repeating: "y", count: JSONLReader.chunkSize * 3 + 17)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("long-\(UUID().uuidString).jsonl")
        try Data("a\n\(long)\n\nb".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var seen: [(Int, Int)] = []
        try JSONLReader.forEachLine(at: url) { number, line in seen.append((number, line.count)) }
        XCTAssertEqual(seen.map(\.0), [1, 2, 3, 4])
        XCTAssertEqual(seen.map(\.1), [1, long.count, 0, 1])
    }

    func testConcatenatedFramesAreReadInOrder() throws {
        XCTAssertEqual(try lines(of: fixture("zstd/frames.jsonl.zst")), ["first", "second", "third"])
    }

    func testATruncatedFileIsAnErrorNotSilentData() {
        XCTAssertThrowsError(try lines(of: fixture("zstd/truncated.jsonl.zst")))
    }

    func testAFileThatIsNotZstdIsAnError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-zstd-\(UUID().uuidString).jsonl.zst")
        try Data("{\"plain\":true}\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try lines(of: url))
    }

    func testTheScannerIndexesCompressedRollouts() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("zstd-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(
            at: fixture("zstd/\(rolloutName).zst"),
            to: folder.appendingPathComponent("\(rolloutName).zst"))

        let store = try EventStore(url: folder.appendingPathComponent("index.db"))
        let scanner = TranscriptScanner(store: store)
        let report = try scanner.scan(roots: [ScanRoot(directory: folder, parser: CodexParser())])
        XCTAssertEqual(report.filesParsed, 1)
        XCTAssertGreaterThan(report.eventsStored, 0)
        XCTAssertTrue(report.failures.isEmpty)
    }
}
