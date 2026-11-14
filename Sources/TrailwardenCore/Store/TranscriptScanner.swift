// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// One directory to watch, with the parser that understands its files.
public struct ScanRoot: Sendable {
    public let directory: URL
    public let parser: any AgentParser

    public var agent: Agent { parser.agent }

    public init(directory: URL, parser: any AgentParser) {
        self.directory = directory
        self.parser = parser
    }

    /// The two directories Trailwarden reads by default.
    public static func standard() -> [ScanRoot] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ScanRoot(
                directory: home.appendingPathComponent(".claude/projects", isDirectory: true),
                parser: ClaudeCodeParser()
            ),
            ScanRoot(
                directory: home.appendingPathComponent(".codex/sessions", isDirectory: true),
                parser: CodexParser()
            ),
        ]
    }
}

/// Outcome of one scan pass.
public struct ScanReport: Sendable, Equatable {
    public var filesSeen = 0
    public var filesParsed = 0
    public var filesUnchanged = 0
    public var eventsStored = 0
    public var skippedLines = 0
    /// Files that could not be parsed at all; a broken file never aborts the scan.
    public var failures: [String] = []

    public init() {}
}

/// Walks transcript directories and only re-parses files whose size or
/// modification time changed since the last pass.
public struct TranscriptScanner {
    private let store: EventStore
    private let redactor: Redactor

    public init(store: EventStore, redactor: Redactor = Redactor()) {
        self.store = store
        self.redactor = redactor
    }

    public func scan(roots: [ScanRoot]) throws -> ScanReport {
        var report = ScanReport()
        for root in roots {
            scan(root: root, into: &report)
        }
        return report
    }

    private func scan(root: ScanRoot, into report: inout ScanReport) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root.directory,
            includingPropertiesForKeys: Array(keys)
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            report.filesSeen += 1

            let size = values?.fileSize ?? 0
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

            if let known = try? store.fileSignature(path: url.path),
               known.size == size,
               abs(known.mtime - mtime) < 0.5 {
                report.filesUnchanged += 1
                continue
            }

            do {
                let result = try root.parser.parse(file: url)
                let events = result.events.map { redactor.redact($0) }
                let stored = try store.insert(events: events)
                try store.recordScan(
                    path: url.path,
                    agent: root.agent,
                    size: size,
                    mtime: mtime,
                    sessionId: events.first?.sessionId,
                    events: stored,
                    skipped: result.skippedLines
                )
                report.filesParsed += 1
                report.eventsStored += stored
                report.skippedLines += result.skippedLines
            } catch {
                report.failures.append("\(url.lastPathComponent): \(error)")
            }
        }
    }
}
