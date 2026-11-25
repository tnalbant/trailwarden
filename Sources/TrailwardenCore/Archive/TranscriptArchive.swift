// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

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

    /// Bytes on disk, every version counted.
    public func usedBytes() throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    @discardableResult
    public func update(source: URL, agent: Agent, sessionID: String?, store: EventStore) throws -> Outcome {
        guard Self.archived.contains(agent) else { return .unchanged }
        let last = try lastCopy(of: source.standardizedFileURL.path, store: store)

        guard let last else {
            return try write(
                source: source, version: 1,
                agent: agent, sessionID: sessionID, store: store, outcome: .created)
        }
        let present = FileManager.default.fileExists(atPath: last.path)
        let check = try Self.digests(of: source, prefixLength: last.size)
        let prefixMatches = check.size >= last.size && check.prefix == last.digest
        if prefixMatches, check.size == last.size, present {
            return .unchanged
        }
        if prefixMatches {
            return try write(
                source: source, version: last.version,
                agent: agent, sessionID: sessionID, store: store,
                outcome: present ? .extended : .created)
        }
        return try write(
            source: source, version: last.version + 1,
            agent: agent, sessionID: sessionID, store: store, outcome: .newVersion)
    }

    // MARK: - Writing

    private static let archived: Set<Agent> = [.claudeCode, .codex, .gemini, .copilot]

    private func write(
        source: URL, version: Int, agent: Agent,
        sessionID: String?, store: EventStore, outcome: Outcome) throws -> Outcome
    {
        let key = source.standardizedFileURL.path
        let folder = folder(
            for: sessionID ?? source.deletingPathExtension().lastPathComponent, agent: agent)
        try makePrivateDirectory(folder)
        let target = folder.appendingPathComponent("\(version).jsonl.lzfse")
        let temporary = folder.appendingPathComponent(".\(version).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        let size: Int64
        let digest: String
        do {
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            let result = try Self.compress(source: source, into: output)
            size = result.size
            digest = result.digest
            try output.synchronize()
            if rename(temporary.path, target.path) != 0 {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let statement = try store.database.prepare("""
        INSERT OR REPLACE INTO archive_copies
            (source_path, version, archive_path, session_id, agent, source_size, prefix_digest, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """)
        try statement.bind([
            .text(key), .int(version), .text(target.path),
            sessionID.map { .text($0) } ?? .null, .text(agent.rawValue),
            .int(Int(size)), .text(digest), .double(Date().timeIntervalSince1970)
        ])
        try statement.step()
        return outcome
    }

    private func makePrivateDirectory(_ url: URL) throws {
        let manager = FileManager.default
        for directory in [root, url.deletingLastPathComponent(), url]
            where !manager.fileExists(atPath: directory.path)
        {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: directory == root,
                attributes: [.posixPermissions: 0o700])
        }
    }

    /// Streams the source through LZFSE into `output`; the digest and size
    /// describe exactly the bytes that were compressed.
    private static func compress(
        source: URL,
        into output: FileHandle) throws -> (size: Int64, digest: String)
    {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        let filter = try OutputFilter(.compress, using: .lzfse) { data in
            if let data {
                try output.write(contentsOf: data)
            }
        }
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += Int64(chunk.count)
            try filter.write(chunk)
        }
        try filter.finalize()
        return (size, hex(hasher.finalize()))
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

    private func lastCopy(of key: String, store: EventStore) throws -> (
        version: Int, path: String, size: Int64, digest: String)?
    {
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
