// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import CryptoKit
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
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// The copy of `version` for the source named `stem` in a session.
    private func copy(
        _ version: Int, session: String = "sess", agent: Agent = .claudeCode, stem: String = "s1",
        ext: String = "jsonl") -> URL
    {
        let session = archive.folder(for: session, agent: agent)
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: session.path)) ?? []
        let dir = dirs.first { $0.hasPrefix(stem + "-") } ?? "missing"
        return session.appendingPathComponent(dir).appendingPathComponent("\(version).\(ext).lzfse")
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
            atPath: copy(1, session: "rollout-42", agent: .codex, stem: "rollout-42").path))
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
        XCTAssertEqual(try decompressed(copy(1, session: "abc", stem: "abc")), line)
    }

    func testTwoSourcesOfOneSessionKeepTheirOwnCopies() throws {
        let main = try source("main\n", name: "main.jsonl")
        let sub = try source("subagent\n", name: "agent-1.jsonl")
        XCTAssertEqual(try run(main), .created)
        XCTAssertEqual(try run(sub), .created)
        XCTAssertEqual(try decompressed(copy(1, stem: "main")), "main\n")
        XCTAssertEqual(try decompressed(copy(1, stem: "agent")), "subagent\n")
        // Same file name in two folders (Copilot's events.jsonl) is told apart by path.
        let one = try source("one\n", name: "a/events.jsonl")
        let two = try source("two\n", name: "b/events.jsonl")
        XCTAssertEqual(
            try archive.update(source: one, agent: .copilot, sessionID: nil, store: store),
            .created)
        XCTAssertEqual(
            try archive.update(source: two, agent: .copilot, sessionID: nil, store: store),
            .created)
        let copies = try FileManager.default.subpathsOfDirectory(
            atPath: archive.folder(for: "events", agent: .copilot).path).filter { $0.hasSuffix(".lzfse") }
        XCTAssertEqual(copies.count, 2)
    }

    func testCommitNeverReplacesWithLess() {
        let last: TranscriptArchive.Copy = (1, "/x/1.jsonl.lzfse", 10, "digest")
        func plan(total: Int64, prefix: String?, exists: Bool = true, agent: Agent = .claudeCode) -> Bool {
            TranscriptArchive.commit(
                last: last, copyExists: exists, agent: agent, total: total, prefix: prefix).replaceLast
        }
        XCTAssertTrue(plan(total: 20, prefix: "digest"))
        XCTAssertFalse(plan(total: 5, prefix: nil))
        XCTAssertFalse(plan(total: 20, prefix: "other"))
        XCTAssertFalse(plan(total: 20, prefix: "digest", exists: false))
        XCTAssertTrue(plan(total: 10, prefix: "other", agent: .gemini))
        XCTAssertFalse(plan(total: 9, prefix: nil, agent: .gemini))
    }

    func testSourceShortenedWhileCompressingKeepsTheOldCopy() throws {
        // The source is rewritten shorter after the index recorded a longer one.
        let url = try source("0123456789abcdef\n")
        XCTAssertEqual(try run(url), .created)
        try Data("0123\n".utf8).write(to: url)
        XCTAssertEqual(try run(url), .newVersion)
        XCTAssertEqual(try decompressed(copy(1)), "0123456789abcdef\n")
    }

    func testAnUnindexedFileIsNeverOverwritten() throws {
        let url = try source("data\n")
        let hash = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(8)
        let folder = archive.folder(for: "sess", agent: .claudeCode).appendingPathComponent("s1-\(hash)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let orphan = folder.appendingPathComponent("1.jsonl.lzfse")
        try Data("orphan".utf8).write(to: orphan)
        XCTAssertEqual(try run(url), .created)
        XCTAssertEqual(try Data(contentsOf: orphan), Data("orphan".utf8))
        XCTAssertEqual(try decompressed(copy(2)), "data\n")
    }

    func testGeminiBiggerRewriteReplacesAndShorterStartsAVersion() throws {
        let url = try source("{\"m\":[1]}", name: "session.json")
        func gemini() throws -> TranscriptArchive.Outcome {
            try archive.update(source: url, agent: .gemini, sessionID: "g", store: store)
        }
        XCTAssertEqual(try gemini(), .created)
        try Data("{\"m\":[1,2,3]}".utf8).write(to: url)
        XCTAssertEqual(try gemini(), .extended)
        let first = copy(1, session: "g", agent: .gemini, stem: "session", ext: "json")
        XCTAssertEqual(try decompressed(first), "{\"m\":[1,2,3]}")
        try Data("{\"m\":[]}".utf8).write(to: url)
        XCTAssertEqual(try gemini(), .newVersion)
        XCTAssertEqual(try decompressed(first), "{\"m\":[1,2,3]}")
        XCTAssertEqual(
            try decompressed(copy(2, session: "g", agent: .gemini, stem: "session", ext: "json")),
            "{\"m\":[]}")
    }

    func testLargeSourceWhosePrefixCrossesAChunkBoundary() throws {
        var bytes = Data()
        var state: UInt64 = 42
        for _ in 0 ..< 1_500_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        let url = directory.appendingPathComponent("s1.jsonl")
        try bytes.write(to: url)
        XCTAssertEqual(try run(url), .created)
        let grown = bytes + Data("tail\n".utf8)
        try grown.write(to: url)
        XCTAssertEqual(try run(url), .extended)
        let stored = try (Data(contentsOf: copy(1)) as NSData).decompressed(using: .lzfse) as Data
        XCTAssertEqual(stored, grown)
        var changed = grown
        changed[1_200_000] ^= 0xFF
        try changed.write(to: url)
        XCTAssertEqual(try run(url), .newVersion)
        let kept = try (Data(contentsOf: copy(1)) as NSData).decompressed(using: .lzfse) as Data
        XCTAssertEqual(kept, grown)
    }

    func testEmptySourceRoundTripsAndCanGrow() throws {
        let url = try source("")
        XCTAssertEqual(try run(url), .created)
        XCTAssertEqual(try decompressed(copy(1)), "")
        XCTAssertEqual(try run(url), .unchanged)
        try Data("later\n".utf8).write(to: url)
        XCTAssertEqual(try run(url), .extended)
        XCTAssertEqual(try decompressed(copy(1)), "later\n")
    }

    func testMissingCopyFileStartsANewVersion() throws {
        let url = try source("keep\n")
        XCTAssertEqual(try run(url), .created)
        try FileManager.default.removeItem(at: copy(1))
        XCTAssertEqual(try run(url), .newVersion)
        XCTAssertEqual(try decompressed(copy(2)), "keep\n")
    }

    func testEnablingTheArchiveLaterBackFillsScannedFiles() throws {
        let projects = directory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let line = """
        {"type":"user","sessionId":"late","timestamp":"2026-11-14T08:00:00.000Z","cwd":"/tmp/demo",\
        "message":{"role":"user","content":"hello"}}

        """
        try Data(line.utf8).write(to: projects.appendingPathComponent("late.jsonl"))
        let roots = [ScanRoot(directory: projects, parser: ClaudeCodeParser())]
        _ = try TranscriptScanner(store: store).scan(roots: roots)
        XCTAssertEqual(try archive.usedBytes(), 0)
        let report = try TranscriptScanner(store: store, archive: archive).scan(roots: roots)
        XCTAssertEqual(report.filesUnchanged, 1)
        XCTAssertEqual(try decompressed(copy(1, session: "late", stem: "late")), line)
    }

    func testConcurrentArchiversNeverLoseOrShrinkACopy() throws {
        let dbURL = directory.appendingPathComponent("index.sqlite")
        let stores = try (0 ..< 8).map { _ in try EventStore(url: dbURL) }
        let url = try source("line 0\n")
        let root = directory.appendingPathComponent("Archive")
        let box = Unchecked(stores)
        let failures = Unchecked([String]())
        let gate = NSLock()
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            gate.lock()
            let text = (0 ... index).map { "line \($0)\n" }.joined()
            try? Data(text.utf8).write(to: url)
            gate.unlock()
            do {
                _ = try TranscriptArchive(root: root).update(
                    source: url, agent: .claudeCode, sessionID: "race", store: box.value[index])
            } catch {
                gate.lock()
                failures.value.append("\(error)")
                gate.unlock()
            }
        }
        XCTAssertEqual(failures.value, [])
        let statement = try stores[0].database.prepare(
            "SELECT version, archive_path, source_size FROM archive_copies ORDER BY version")
        var rowPaths: Set<String> = []
        while try statement.step() {
            let path = try XCTUnwrap(statement.text(1))
            rowPaths.insert(path)
            let stored = try (Data(contentsOf: URL(fileURLWithPath: path)) as NSData)
                .decompressed(using: .lzfse) as Data
            XCTAssertEqual(stored.count, statement.int(2))
        }
        let files = try FileManager.default.subpathsOfDirectory(
            atPath: root.appendingPathComponent("claude-code/race").path)
            .filter { $0.hasSuffix(".lzfse") }
        XCTAssertFalse(rowPaths.isEmpty)
        XCTAssertEqual(files.count, rowPaths.count)
    }
}

private final class Unchecked<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }
}
