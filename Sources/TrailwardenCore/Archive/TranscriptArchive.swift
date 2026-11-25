// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Compression
import CryptoKit
import Foundation

/// Optional full copies of transcripts, kept because agents delete or rewrite
/// their own. Copies are LZFSE-compressed and append-only: a source that only
/// grew rewrites its newest version in place; a source that shrank or changed
/// earlier bytes keeps the old version and starts the next one. Trailwarden
/// only ever reads the source.
public struct TranscriptArchive: Sendable {
    public enum Outcome: Equatable, Sendable {
        case created, extended, newVersion, unchanged
    }

    private let root: URL
    private static let chunkSize = 1 << 20
    /// One writer at a time in this process: the app's manual scan and the live
    /// watcher both archive, and decide, write and record must not interleave.
    private static let writer = NSLock()
    /// When this process last swept leftover temporary files; guarded by `writer`.
    private nonisolated(unsafe) static var lastSweep: Date?

    public init(root: URL, store _: EventStore? = nil) {
        self.root = root
    }

    /// `<root>/<agent>/<session id or file stem>/` for one session.
    public func folder(for sessionID: String, agent: Agent) -> URL {
        let safe = sessionID.map { $0 == "/" || $0 == ":" ? "_" : $0 }
        let name = String(safe).hasPrefix(".") ? "_" + String(safe) : String(safe)
        return root
            .appendingPathComponent(agent.rawValue, isDirectory: true)
            .appendingPathComponent(name.isEmpty ? "_" : name, isDirectory: true)
    }

    /// Bytes on disk, every version counted. A temporary file of a write in
    /// progress (or one a crash left behind) is not a copy and does not count.
    public func usedBytes() throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            // A file that vanishes or cannot be read mid-walk is skipped, not fatal.
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            else { continue }
            if values.isRegularFile == true, !Self.isTemporary(url) {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    @discardableResult
    public func update(source: URL, agent: Agent, sessionID: String?, store: EventStore) throws -> Outcome {
        guard Self.archived.contains(agent) else { return .unchanged }
        Self.writer.lock()
        defer { Self.writer.unlock() }
        let now = Date()
        if Self.lastSweep.map({ now.timeIntervalSince($0) > 3600 }) ?? true {
            Self.lastSweep = now
            sweepTemporaryFiles(now: now)
        }
        // Read inside the lock, so the decision sees the newest row.
        let last = try lastCopy(of: source.standardizedFileURL.path, store: store)
        // Cheap exit: same size and same bytes as the copy that is on disk.
        if let last, FileManager.default.fileExists(atPath: last.path),
           Self.fileSize(source) == last.size,
           try Self.digests(of: source, prefixLength: last.size).prefix == last.digest
        {
            return .unchanged
        }
        return try write(source: source, agent: agent, sessionID: sessionID, last: last, store: store)
    }

    /// Removes `.<uuid>.tmp` files older than `age`: a write that crashed
    /// before its rename. A newer one may belong to a write running in another
    /// process, so it stays. Call with `writer` held. Returns how many went.
    @discardableResult
    func sweepTemporaryFiles(olderThan age: TimeInterval = 3600, now: Date = Date()) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
        var removed = 0
        for case let url as URL in enumerator where Self.isTemporary(url) {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
                now.timeIntervalSince(modified) > age else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    private static func isTemporary(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") && name.hasSuffix(".tmp")
    }

    /// True when the source has no copy yet, or its newest copy is missing or
    /// has another size. A size check only: the scanner uses it for files it
    /// considers unchanged, where hashing every file each pass would cost too much.
    func needsCopy(source: URL, agent: Agent, store: EventStore) -> Bool {
        guard Self.archived.contains(agent) else { return false }
        guard let last = try? lastCopy(of: source.standardizedFileURL.path, store: store) else { return true }
        return !FileManager.default.fileExists(atPath: last.path) || Self.fileSize(source) != last.size
    }

    // MARK: - Writing

    private static let archived: Set<Agent> = [.claudeCode, .codex, .gemini, .copilot]

    typealias Copy = (version: Int, path: String, size: Int64, digest: String)

    /// What to do with the bytes that were just compressed. Decided only after
    /// the whole stream has passed, from the same bytes that were written.
    static func commit(
        last: Copy?, copyExists: Bool, agent: Agent, total: Int64,
        prefix: String?) -> (replaceLast: Bool, Outcome)
    {
        guard let last else { return (false, .created) }
        guard copyExists else { return (false, .newVersion) }
        // Gemini rewrites its whole JSON document: bigger or equal replaces.
        if agent == .gemini {
            return total >= last.size ? (true, .extended) : (false, .newVersion)
        }
        if total >= last.size, prefix == last.digest {
            return (true, .extended)
        }
        return (false, .newVersion)
    }

    private func write(
        source: URL, agent: Agent, sessionID: String?, last: Copy?, store: EventStore) throws -> Outcome
    {
        let key = source.standardizedFileURL.path
        let folder = sourceFolder(for: source, sessionID: sessionID, agent: agent)
        try makePrivateDirectory(folder)
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            let result = try Self.compress(source: source, into: output, prefixLength: last?.size ?? 0)
            try output.synchronize()
            let copyExists = last.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let plan = Self.commit(
                last: last, copyExists: copyExists, agent: agent, total: result.size, prefix: result.prefix)
            let version: Int
            let target: URL
            if plan.replaceLast, let last {
                version = last.version
                target = URL(fileURLWithPath: last.path)
                if rename(temporary.path, target.path) != 0 {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
                }
            } else {
                // Exclusive rename: another process (the CLI) can never be
                // clobbered; on a name that is taken, try the next version.
                var next = (last?.version ?? 0) + 1
                var candidate = folder.appendingPathComponent(Self.fileName(next, source))
                while renamex_np(temporary.path, candidate.path, UInt32(RENAME_EXCL)) != 0 {
                    guard errno == EEXIST else {
                        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: candidate.path])
                    }
                    next += 1
                    candidate = folder.appendingPathComponent(Self.fileName(next, source))
                }
                version = next
                target = candidate
            }
            try record(
                key: key, copy: (version, target.path, result.size, result.digest),
                sessionID: sessionID, agent: agent, store: store)
            return plan.1
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func record(
        key: String, copy: Copy, sessionID: String?, agent: Agent, store: EventStore) throws
    {
        let statement = try store.database.prepare("""
        INSERT OR REPLACE INTO archive_copies
            (source_path, version, archive_path, session_id, agent, source_size, prefix_digest, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """)
        try statement.bind([
            .text(key), .int(copy.version), .text(copy.path),
            sessionID.map { .text($0) } ?? .null, .text(agent.rawValue),
            .int(Int(copy.size)), .text(copy.digest), .double(Date().timeIntervalSince1970)
        ])
        try statement.step()
    }

    /// `<session folder>/<source stem>-<8 hex of SHA-256(source path)>/`: two
    /// sources of one session (a Claude subagent file, Copilot's
    /// `events.jsonl`) never share a copy.
    private func sourceFolder(for source: URL, sessionID: String?, agent: Agent) -> URL {
        let stem = Self.stem(source)
        let hash = Self.hex(SHA256.hash(data: Data(source.standardizedFileURL.path.utf8))).prefix(8)
        return folder(for: sessionID ?? stem, agent: agent)
            .appendingPathComponent("\(stem)-\(hash)", isDirectory: true)
    }

    private static func stem(_ source: URL) -> String {
        let name = source.lastPathComponent
        let stem = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return stem.isEmpty ? "source" : String(stem)
    }

    /// `1.jsonl.lzfse`: the source's own extension(s) stay in the name.
    private static func fileName(_ version: Int, _ source: URL) -> String {
        let name = source.lastPathComponent
        guard let dot = name.firstIndex(of: "."), name.index(after: dot) < name.endIndex else {
            return "\(version).lzfse"
        }
        return "\(version).\(name[name.index(after: dot)...]).lzfse"
    }

    private static func fileSize(_ url: URL) -> Int64 {
        // Not `resourceValues`: a URL caches the size it reported first.
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
    }

    private func makePrivateDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var chain = [url]
        while chain[0].path != root.path, chain[0].pathComponents.count > root.pathComponents.count {
            chain.insert(chain[0].deletingLastPathComponent(), at: 0)
        }
        for directory in chain where !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: directory == root,
                attributes: [.posixPermissions: 0o700])
        }
    }

    /// Streams the source through LZFSE into `output`. The digest and size
    /// describe exactly the bytes compressed; `prefix` is the digest of the
    /// first `prefixLength` of them, or nil when fewer arrived.
    private static func compress(
        source: URL, into output: FileHandle, prefixLength: Int64) throws
        -> (size: Int64, digest: String, prefix: String?)
    {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256()
        var prefix: String? = prefixLength == 0 ? hex(hasher.finalize()) : nil
        var size: Int64 = 0
        let filter = try OutputFilter(.compress, using: .lzfse) { data in
            if let data {
                try output.write(contentsOf: data)
            }
        }
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            if prefix == nil, size + Int64(chunk.count) >= prefixLength {
                let head = chunk.prefix(Int(prefixLength - size))
                var snapshot = hasher
                snapshot.update(data: head)
                prefix = hex(snapshot.finalize())
            }
            hasher.update(data: chunk)
            size += Int64(chunk.count)
            try filter.write(chunk)
        }
        try filter.finalize()
        return (size, hex(hasher.finalize()), prefix)
    }

    /// Size of the source and the SHA-256 of its first `prefixLength` bytes.
    private static func digests(of source: URL, prefixLength: Int64) throws -> (size: Int64, prefix: String) {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256()
        var remaining = prefixLength
        var size: Int64 = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            size += Int64(chunk.count)
            if remaining > 0 {
                let part = chunk.prefix(Int(min(remaining, Int64(chunk.count))))
                hasher.update(data: part)
                remaining -= Int64(part.count)
            }
        }
        return (size, remaining == 0 ? hex(hasher.finalize()) : "")
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Index

    private func lastCopy(of key: String, store: EventStore) throws -> Copy? {
        let statement = try store.database.prepare("""
        SELECT version, archive_path, source_size, prefix_digest FROM archive_copies
        WHERE source_path = ? ORDER BY version DESC LIMIT 1
        """)
        try statement.bind([.text(key)])
        guard try statement.step(), let version = statement.int(0), let path = statement.text(1),
              let size = statement.int(2), let digest = statement.text(3) else { return nil }
        return (version, path, Int64(size), digest)
    }
}
