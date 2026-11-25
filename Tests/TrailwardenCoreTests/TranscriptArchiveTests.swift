// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
@testable import TrailwardenCore
import XCTest

final class TranscriptArchiveTests: XCTestCase {
    private var directory: URL!
    private var store: EventStore!
    private var archive: TranscriptArchive!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tw-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try EventStore()
        archive = TranscriptArchive(root: directory.appendingPathComponent("Archive"), store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func source(_ text: String, name: String = "s1.jsonl") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func copy(_ version: Int, session: String = "sess", agent: Agent = .claudeCode) -> URL {
        archive.folder(for: session, agent: agent).appendingPathComponent("\(version).jsonl.lzfse")
    }

    private func decompressed(_ url: URL) throws -> String {
        let data = try (Data(contentsOf: url) as NSData).decompressed(using: .lzfse) as Data
        return String(decoding: data, as: UTF8.self)
    }

    private func permissions(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
    }

    private func run(_ url: URL, session: String = "sess", agent: Agent = .claudeCode) throws
        -> TranscriptArchive.Outcome
    {
        try archive.update(source: url, agent: agent, sessionID: session, store: store)
    }

    func testFirstCopyIsCreatedPrivate() throws {
        let text = String(repeating: "{\"a\":1}\n", count: 500)
        let url = try source(text)
        XCTAssertEqual(try run(url), .created)
        let file = copy(1)
        XCTAssertEqual(try permissions(file), 0o600)
        XCTAssertEqual(try permissions(file.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(file.deletingLastPathComponent().deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try decompressed(file), text)
    }

    func testAppendExtendsTheSameVersion() throws {
        let url = try source("one\ntwo\n")
        XCTAssertEqual(try run(url), .created)
        try Data("one\ntwo\nthree\n".utf8).write(to: url)
        XCTAssertEqual(try run(url), .extended)
        XCTAssertEqual(try decompressed(copy(1)), "one\ntwo\nthree\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy(2).path))
    }

    func testRewriteStartsANewVersionAndKeepsTheOld() throws {
        let url = try source("alpha\nbeta\ngamma\n")
        XCTAssertEqual(try run(url), .created)
        try Data("alpha\n".utf8).write(to: url)
        XCTAssertEqual(try run(url), .newVersion)
        XCTAssertEqual(try decompressed(copy(1)), "alpha\nbeta\ngamma\n")
        XCTAssertEqual(try decompressed(copy(2)), "alpha\n")

        // Same length as version 2's source, different bytes.
        try Data("ALPHA\n".utf8).write(to: url)
        XCTAssertEqual(try run(url), .newVersion)
        XCTAssertEqual(try decompressed(copy(1)), "alpha\nbeta\ngamma\n")
        XCTAssertEqual(try decompressed(copy(2)), "alpha\n")
        XCTAssertEqual(try decompressed(copy(3)), "ALPHA\n")
    }

    func testUnchangedFileIsNotRewritten() throws {
        let url = try source("same\n")
        XCTAssertEqual(try run(url), .created)
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: copy(1).path)
        XCTAssertEqual(try run(url), .unchanged)
        let modified = try FileManager.default
            .attributesOfItem(atPath: copy(1).path)[.modificationDate] as? Date
        XCTAssertEqual(modified, past)
    }

    func testDatabaseAgentsAreSkipped() throws {
        let url = try source("x\n", name: "db.jsonl")
        for agent in [Agent.cursor, .opencode, .hermes] {
            XCTAssertEqual(try run(url, agent: agent), .unchanged)
            XCTAssertFalse(FileManager.default
                .fileExists(atPath: archive.folder(for: "sess", agent: agent).path))
        }
        XCTAssertEqual(try archive.usedBytes(), 0)
    }

    func testUsedBytesCountsEveryVersion() throws {
        let url = try source(String(repeating: "line one\n", count: 200))
        _ = try run(url)
        let first = try archive.usedBytes()
        XCTAssertGreaterThan(first, 0)
        try Data("different\n".utf8).write(to: url)
        XCTAssertEqual(try run(url), .newVersion)
        let both = [copy(1), copy(2)].reduce(Int64(0)) {
            $0 + Int64((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int) ?? 0)
        }
        XCTAssertEqual(try archive.usedBytes(), both)
        XCTAssertGreaterThan(both, first)
    }

    func testSessionIDFallsBackToFileStem() throws {
        let url = try source("x\n", name: "rollout-42.jsonl")
        XCTAssertEqual(try archive.update(source: url, agent: .codex, sessionID: nil, store: store), .created)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: archive.folder(for: "rollout-42", agent: .codex)
                .appendingPathComponent("1.jsonl.lzfse").path))
    }

    func testScannerArchivesARescannedFile() throws {
        let projects = directory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let line = """
        {"type":"user","sessionId":"abc","timestamp":"2026-11-14T08:00:00.000Z","cwd":"/tmp/demo",\
        "message":{"role":"user","content":"hello"}}

        """
        let url = projects.appendingPathComponent("abc.jsonl")
        try Data(line.utf8).write(to: url)
        let scanner = TranscriptScanner(store: store, archive: archive)
        let report = scanner.scan(
            changed: [url], roots: [ScanRoot(directory: projects, parser: ClaudeCodeParser())])
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(try decompressed(copy(1, session: "abc")), line)
    }
}
