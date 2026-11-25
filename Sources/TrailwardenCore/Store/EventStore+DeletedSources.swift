// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Agents delete their own transcripts. The index keeps what it read; these
/// helpers remember when a source file was first seen missing so the app can
/// say so. Only `scanned_files` carries the mark, so database-backed agents,
/// which have no such rows, are never marked.
extension EventStore {
    /// Marks every scanned file under `roots` that is gone from disk (keeping
    /// the first time it was seen missing) and clears the mark of any that is
    /// back. Returns how many files were newly marked.
    @discardableResult
    public func markMissingSources(under roots: [URL], now: Date) throws -> Int {
        // Stored paths keep the root as the scanner was given it, which may be a
        // symlinked spelling (`/var/…` for `/private/var/…`); both count.
        let prefixes = roots.flatMap { [$0.path, Self.realPath($0)] }.map { $0 + "/" }
        let rows = try database.prepare("SELECT path, missing_since IS NOT NULL FROM scanned_files")
        var vanished: [String] = []
        var returned: [String] = []
        while try rows.step() {
            guard let path = rows.text(0), prefixes.contains(where: { path.hasPrefix($0) }) else { continue }
            let marked = (rows.int(1) ?? 0) != 0
            let exists = FileManager.default.fileExists(atPath: path)
            if !exists, !marked {
                vanished.append(path)
            } else if exists, marked {
                returned.append(path)
            }
        }
        let mark = try database.prepare(
            "UPDATE scanned_files SET missing_since = ? WHERE path = ? AND missing_since IS NULL")
        for path in vanished {
            try mark.bind([.double(now.timeIntervalSince1970), .text(path)])
            try mark.step()
        }
        let clear = try database.prepare("UPDATE scanned_files SET missing_since = NULL WHERE path = ?")
        for path in returned {
            try clear.bind([.text(path)])
            try clear.step()
        }
        return vanished.count
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
