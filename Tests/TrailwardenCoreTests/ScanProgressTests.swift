// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class ScanProgressTests: XCTestCase {
    private func fixture(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(path)")
    }

    func testProgressCountsEveryFileAndEndsAtOneHundredPercent() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rollout = "rollout-2026-11-14T09-00-00-3f2a1c8e-7b4d-4a11-9c2e-1f0b6d5a8e33.jsonl"
        try FileManager.default.copyItem(
            at: fixture("codex/\(rollout)"),
            to: folder.appendingPathComponent(rollout))
        try FileManager.default.copyItem(
            at: fixture("zstd/large.jsonl.zst"),
            to: folder.appendingPathComponent("b.jsonl.zst"))
        try Data("not a transcript".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let store = try EventStore(url: folder.appendingPathComponent("index.db"))
        var seen: [ScanProgress] = []
        _ = try TranscriptScanner(store: store)
            .scan(roots: [ScanRoot(directory: folder, parser: CodexParser())]) { seen.append($0) }

        XCTAssertEqual(seen.first?.filesDone, 0, "the total is known before the first file")
        XCTAssertEqual(seen.first?.filesTotal, 2, "only files the parser reads are counted")
        XCTAssertEqual(seen.map(\.filesDone), [0, 1, 2])
        XCTAssertEqual(seen.last?.fraction, 1)
        XCTAssertEqual(seen.map(\.fraction), seen.map(\.fraction).sorted(), "never moves backwards")
    }

    func testAnEmptyScanIsFinished() {
        XCTAssertEqual(ScanProgress().fraction, 1)
    }
}
