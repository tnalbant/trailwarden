// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import CoreServices
import Foundation

/// Watches the transcript folders and reports which files changed, a moment
/// after the agent stops writing.
///
/// FSEvents is the kernel's own change journal: no polling, no timer, and no
/// cost while the agents are quiet. Bursts are coalesced — an agent appends a
/// line per tool call, and one pass per burst is enough.
public final class TranscriptWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([URL]) -> Void

    private let directories: [URL]
    private let latency: TimeInterval
    private let accepts: @Sendable (URL) -> Bool
    private let handler: Handler
    private let queue = DispatchQueue(label: "app.trailwarden.watcher")
    private var stream: FSEventStreamRef?

    /// - Parameters:
    ///   - directories: folders to watch, recursively; missing ones are skipped.
    ///   - latency: seconds FSEvents waits to batch changes before calling back.
    ///   - accepts: filter for changed files (e.g. `.jsonl` only).
    public init(
        directories: [URL],
        latency: TimeInterval = 1.0,
        accepts: @escaping @Sendable (URL) -> Bool,
        handler: @escaping Handler)
    {
        self.directories = directories
        self.latency = latency
        self.accepts = accepts
        self.handler = handler
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    deinit {
        stop()
    }

    /// Starts watching. Returns `false` when none of the folders exist.
    @discardableResult
    public func start() -> Bool {
        queue.sync {
            guard stream == nil else { return true }
            let paths = directories
                .map(\.path)
                .filter { FileManager.default.fileExists(atPath: $0) } as CFArray
            guard CFArrayGetCount(paths) > 0 else { return false }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil)
            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagNoDefer)
            guard let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags)
            else { return false }

            FSEventStreamSetDispatchQueue(created, queue)
            guard FSEventStreamStart(created) else {
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
                return false
            }
            stream = created
            return true
        }
    }

    public func stop() {
        let stopNow = { [self] in
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            stopNow()
        } else {
            queue.sync(execute: stopNow)
        }
    }

    public var isRunning: Bool {
        queue.sync { stream != nil }
    }

    private static let queueKey = DispatchSpecificKey<Void>()

    private func received(_ paths: [String]) {
        var seen = Set<String>()
        let changed = paths
            .filter { seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0) }
            .filter(accepts)
        if !changed.isEmpty {
            handler(changed)
        }
    }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<TranscriptWatcher>.fromOpaque(info).takeUnretainedValue()
        let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
        let paths = (0 ..< count).compactMap { array[$0] as? String }
        watcher.received(paths)
    }
}

public extension TranscriptWatcher {
    /// A watcher over the standard transcript folders and the Hermes database,
    /// accepting only the files a scan would read.
    static func standard(latency: TimeInterval = 1.0, handler: @escaping Handler) -> TranscriptWatcher {
        let roots = ScanRoot.standard()
        let databases = ScanRoot.standardDatabases()
        let rootPaths = roots.map { ($0.directory.standardizedFileURL.path + "/", $0.parser) }
        let databasePaths = databases.map(\.database.standardizedFileURL.path)
        let directories = roots.map(\.directory) + databases.map { $0.database.deletingLastPathComponent() }
        return TranscriptWatcher(
            directories: directories,
            latency: latency,
            accepts: { url in
                let path = url.standardizedFileURL.path
                if databasePaths.contains(where: { path == $0 || path == $0 + "-wal" }) {
                    return true
                }
                return rootPaths.contains { prefix, parser in
                    path.hasPrefix(prefix) && parser.accepts(url)
                }
            },
            handler: handler)
    }
}
