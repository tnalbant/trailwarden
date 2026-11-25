// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// One directory to watch, with the parser that understands its files.
public struct ScanRoot: Sendable {
    public let directory: URL
    public let parser: any AgentParser

    public var agent: Agent {
        parser.agent
    }

    public init(directory: URL, parser: any AgentParser) {
        self.directory = directory
        self.parser = parser
    }

    /// Agents whose history lives in a database rather than in files.
    public static func standardDatabases(agents: Set<Agent>? = nil) -> [DatabaseSource] {
        let sources = [
            DatabaseSource(database: HermesDatabaseParser.defaultURL, parser: HermesDatabaseParser()),
            DatabaseSource(database: OpencodeDatabaseParser.defaultURL, parser: OpencodeDatabaseParser()),
            DatabaseSource(database: CursorDatabaseParser.defaultURL, parser: CursorDatabaseParser())
        ]
        guard let agents, !agents.isEmpty else { return sources }
        return sources.filter { agents.contains($0.agent) }
    }

    /// The directories Trailwarden reads by default, optionally narrowed to
    /// the agents the user asked for.
    public static func standard(agents: Set<Agent>? = nil) -> [ScanRoot] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            ScanRoot(
                directory: home.appendingPathComponent(".claude/projects", isDirectory: true),
                parser: ClaudeCodeParser()),
            ScanRoot(
                directory: home.appendingPathComponent(".codex/sessions", isDirectory: true),
                parser: CodexParser()),
            // Gemini CLI keeps one JSON document per session under tmp/<project>/chats.
            ScanRoot(
                directory: home.appendingPathComponent(".gemini/tmp", isDirectory: true),
                parser: GeminiCLIParser()),
            // Copilot CLI and the Copilot app: session-state/<session>/events.jsonl.
            ScanRoot(
                directory: home.appendingPathComponent(".copilot/session-state", isDirectory: true),
                parser: CopilotParser())
        ]
        guard let agents, !agents.isEmpty else { return roots }
        return roots.filter { agents.contains($0.agent) }
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

/// How far a scan has got. Measured in bytes as well as files: one long Codex
/// session can outweigh a thousand short ones, and a bar that waits on it at
/// 99 % says less than one that moves with the work.
public struct ScanProgress: Sendable, Equatable {
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0

    public init(filesDone: Int = 0, filesTotal: Int = 0, bytesDone: Int64 = 0, bytesTotal: Int64 = 0) {
        self.filesDone = filesDone
        self.filesTotal = filesTotal
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
    }

    /// 0…1; an empty scan counts as finished.
    public var fraction: Double {
        guard bytesTotal > 0 else { return filesTotal == 0 ? 1 : Double(filesDone) / Double(filesTotal) }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }
}

/// Walks transcript directories and only re-parses files whose size or
/// modification time changed since the last pass.
public struct TranscriptScanner {
    private let store: EventStore
    private let redactor: Redactor
    private let rules: RuleEngine?
    private let archive: TranscriptArchive?

    public init(
        store: EventStore,
        redactor: Redactor = Redactor(),
        rules: RuleEngine? = nil,
        archive: TranscriptArchive? = nil)
    {
        self.store = store
        self.redactor = redactor
        self.rules = rules
        self.archive = archive
    }

    public func scan(
        roots: [ScanRoot],
        databases: [DatabaseSource] = [],
        progress: ((ScanProgress) -> Void)? = nil) throws -> ScanReport
    {
        var report = ScanReport()
        // List first, so progress has a total to count against. Unchanged files
        // count too: they are skipped quickly, and leaving them out would make
        // the total shrink as the scan runs.
        let files = roots.flatMap { root in Self.transcripts(in: root).map { (root, $0.url, $0.size) } }
        let sources = databases.filter { FileManager.default.fileExists(atPath: $0.database.path) }
        var state = ScanProgress(
            filesTotal: files.count + sources.count,
            bytesTotal: files.reduce(0) { $0 + $1.2 } + sources.reduce(0) { $0 + Self.size(of: $1.database) })
        progress?(state)

        // A file that came back after being gone is read in full this pass.
        try? store.releaseReturnedSources(under: roots.map(\.directory))
        for (root, url, size) in files {
            scan(file: url, root: root, into: &report)
            state.filesDone += 1
            state.bytesDone += size
            progress?(state)
        }
        for source in sources {
            scan(database: source, into: &report)
            state.filesDone += 1
            state.bytesDone += Self.size(of: source.database)
            progress?(state)
        }
        // Only a full pass may call a file gone; the live watcher sees files
        // mid-rewrite and must not flicker.
        do {
            try store.markMissingSources(under: roots.map(\.directory), now: Date())
        } catch {
            report.failures.append("missing sources: \(error)")
        }
        return report
    }

    private static func transcripts(in root: ScanRoot) -> [(url: URL, size: Int64)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root.directory,
            includingPropertiesForKeys: Array(fileKeys)) else { return [] }
        var result: [(URL, Int64)] = []
        for case let url as URL in enumerator where root.parser.accepts(url) {
            let values = try? url.resourceValues(forKeys: fileKeys)
            guard values?.isRegularFile == true else { continue }
            result.append((url, Int64(values?.fileSize ?? 0)))
        }
        return result
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Agents that keep history in SQLite are read incrementally: only rows newer
    /// than the newest event already stored for that agent.
    private func scan(database source: DatabaseSource, into report: inout ScanReport) {
        guard FileManager.default.fileExists(atPath: source.database.path) else { return }
        report.filesSeen += 1

        do {
            let since = try store.latestTimestamp(agent: source.agent)
            let result = try source.parser.parse(database: source.database, since: since)
            guard !result.events.isEmpty else {
                try store.markReread(agent: source.agent)
                report.filesParsed += 1
                return
            }
            let annotated = rules?.annotate(result.events) ?? result.events
            let events = annotated.map { redactor.redact($0) }
            let stored = try store.insert(events: events)
            try store.setSessionTitles(result.titles)
            try store.markReread(agent: source.agent)
            report.filesParsed += 1
            report.eventsStored += stored
            report.skippedLines += result.skippedLines
        } catch {
            report.failures.append("\(source.database.lastPathComponent): \(error)")
        }
    }

    /// Re-reads only the files that changed, for the live watcher: no folder walk,
    /// so a pass costs one parse per file the agent just wrote. A path outside
    /// every root is ignored; a database path re-reads that database.
    public func scan(
        changed urls: [URL],
        roots: [ScanRoot],
        databases: [DatabaseSource] = []) -> ScanReport
    {
        var report = ScanReport()
        var databasesToRead: [DatabaseSource] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if let source = databases.first(where: {
                let database = $0.database.standardizedFileURL.path
                return path == database || path == database + "-wal"
            }) {
                if !databasesToRead.contains(where: { $0.database == source.database }) {
                    databasesToRead.append(source)
                }
                continue
            }
            guard let root = roots.first(where: {
                path.hasPrefix($0.directory.standardizedFileURL.path + "/")
                    && $0.parser.accepts(url)
            }) else { continue }
            scan(file: url, root: root, into: &report)
        }
        for source in databasesToRead {
            scan(database: source, into: &report)
        }
        return report
    }

    private static let fileKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    private func scan(file url: URL, root: ScanRoot, into report: inout ScanReport) {
        let keys = Self.fileKeys
        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isRegularFile == true else { return }
        report.filesSeen += 1

        let size = values?.fileSize ?? 0
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

        if let known = try? store.fileSignature(path: url.path),
           known.size == size,
           abs(known.mtime - mtime) < 0.5
        {
            report.filesUnchanged += 1
            // Back-fill: a file scanned before the archive was switched on, or
            // whose copy failed last time, gets its copy now.
            if let archive, archive.needsCopy(source: url, agent: root.agent, store: store) {
                archiveCopy(url, agent: root.agent, sessionID: known.sessionId, report: &report)
            }
            return
        }

        do {
            let result = try root.parser.parse(file: url)
            // Rules run on the raw text, then the store only ever sees the
            // masked copy: a hit carries its message, never the secret.
            let annotated = rules?.annotate(result.events) ?? result.events
            let events = annotated.map { redactor.redact($0) }
            let stored = try store.insert(events: events)
            try store.setSessionTitles(result.titles)
            // Before the signature is saved: a failed copy is retried next pass.
            archiveCopy(url, agent: root.agent, sessionID: events.first?.sessionId, report: &report)
            try store.recordScan(
                path: url.path,
                agent: root.agent,
                size: size,
                mtime: mtime,
                sessionId: events.first?.sessionId,
                events: stored,
                skipped: result.skippedLines)
            report.filesParsed += 1
            report.eventsStored += stored
            report.skippedLines += result.skippedLines
        } catch {
            report.failures.append("\(url.lastPathComponent): \(error)")
        }
    }

    private func archiveCopy(_ url: URL, agent: Agent, sessionID: String?, report: inout ScanReport) {
        guard let archive else { return }
        do {
            try archive.update(source: url, agent: agent, sessionID: sessionID, store: store)
        } catch {
            report.failures.append("archive \(url.lastPathComponent): \(error)")
        }
    }
}
