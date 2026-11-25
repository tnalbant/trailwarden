// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Agents delete their own transcripts. The index keeps what it read; these
/// helpers remember when a source file was first seen missing so the app can
/// say so. Only `scanned_files` carries the mark, so database-backed agents,
/// which have no such rows, are never marked.
extension EventStore {
    /// Marks every scanned file under `roots` that is gone from disk (keeping
    /// the first time it was seen missing). A file that is back loses its row,
    /// so the next scan reads it again. Roots that do not exist or cannot be
    /// listed (unmounted volume, removed agent folder, denied access) are
    /// skipped: not knowing is not the same as deleted. Returns how many files
    /// were newly marked.
    @discardableResult
    public func markMissingSources(under roots: [URL], now: Date) throws -> Int {
        let rows = try scannedRows(under: roots)
        let vanished = rows.filter { !$0.marked && !FileManager.default.fileExists(atPath: $0.path) }
        let mark = try database.prepare(
            "UPDATE scanned_files SET missing_since = ? WHERE path = ? AND missing_since IS NULL")
        for row in vanished {
            try mark.bind([.double(now.timeIntervalSince1970), .text(row.path)])
            try mark.step()
        }
        try releaseReturnedSources(rows)
        return vanished.count
    }

    /// Forgets the signature of marked files that exist again, so a scan reads
    /// them in full and honours any reread requested while they were gone.
    public func releaseReturnedSources(under roots: [URL]) throws {
        try releaseReturnedSources(scannedRows(under: roots))
    }

    private func releaseReturnedSources(_ rows: [(path: String, marked: Bool)]) throws {
        let delete = try database.prepare("DELETE FROM scanned_files WHERE path = ?")
        for row in rows where row.marked && FileManager.default.fileExists(atPath: row.path) {
            try delete.bind([.text(row.path)])
            try delete.step()
        }
    }

    private func scannedRows(under roots: [URL]) throws -> [(path: String, marked: Bool)] {
        // Stored paths keep the root as the scanner was given it, which may be a
        // symlinked spelling (`/var/…` for `/private/var/…`); both count.
        let prefixes = roots
            .filter { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil }
            .flatMap { [$0.path, Self.realPath($0)] }.map { $0 + "/" }
        let statement = try database.prepare("SELECT path, missing_since IS NOT NULL FROM scanned_files")
        var rows: [(path: String, marked: Bool)] = []
        while try statement.step() {
            guard let path = statement.text(0),
                  prefixes.contains(where: { path.hasPrefix($0) }) else { continue }
            rows.append((path, (statement.int(1) ?? 0) != 0))
        }
        return rows
    }

    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Sessions whose every scanned file is marked missing.
    func sessionsWithDeletedSources() throws -> Set<String> {
        let statement = try database.prepare("""
        SELECT session_id FROM scanned_files
        WHERE session_id IS NOT NULL
        GROUP BY session_id
        HAVING COUNT(*) = COUNT(missing_since)
        """)
        var ids: Set<String> = []
        while try statement.step() {
            if let id = statement.text(0) {
                ids.insert(id)
            }
        }
        return ids
    }
}
