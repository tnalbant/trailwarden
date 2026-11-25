// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import CryptoKit
import Foundation

/// A secret found in a file rather than in a transcript event.
public struct FileFinding: Sendable, Equatable {
    public let key: String
    /// Home-shortened (`~/…`).
    public let path: String
    public let ruleId: String
    public let severity: Severity
    public let line: Int
    /// The matched line after redaction; the secret itself is never kept.
    public let preview: String
}

/// R29: a token or password left in an agent's settings file, for example inside
/// a Claude `permissions.allow` entry. A file check, not an event rule: it is not
/// in `rules.json`, never notifies, and the files are only ever read.
public enum AgentSettingsScan {
    public static let ruleID = "R29"

    private static let maxPreview = 240

    public static func candidateFiles(home: URL, sessionCwds: [String]) -> [URL] {
        var files = [
            home.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/settings.local.json"),
            home.appendingPathComponent(".codex/config.toml"),
            home.appendingPathComponent(".gemini/settings.json")
        ]
        for cwd in Set(sessionCwds).sorted() where cwd.hasPrefix("/") {
            let base = URL(fileURLWithPath: cwd).appendingPathComponent(".claude")
            files.append(base.appendingPathComponent("settings.local.json"))
            files.append(base.appendingPathComponent("settings.json"))
        }
        var seen = Set<String>()
        return files.filter { seen.insert($0.path).inserted }
    }

    public static func scan(
        _ files: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [FileFinding]
    {
        let redactor = Redactor()
        var result: [FileFinding] = []
        for file in files {
            // Read-only; a missing or unreadable file is skipped silently.
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            let path = shortPath(file, home: home)
            var seenKeys = Set<String>()
            for hit in redactor.secretLines(in: text) {
                let line = hit.redacted.trimmingCharacters(in: .whitespaces)
                let digest = SHA256.hash(data: Data(line.utf8)).map { String(format: "%02x", $0) }
                    .joined().prefix(12)
                let key = FindingKey.file(path: path, rule: ruleID, digest: String(digest))
                guard seenKeys.insert(key).inserted else { continue }
                result.append(FileFinding(
                    key: key,
                    path: path,
                    ruleId: ruleID,
                    severity: .warn,
                    line: hit.line,
                    preview: String(line.prefix(maxPreview))))
            }
        }
        return result
    }

    /// `/Users/demo/.claude/x` -> `~/.claude/x` for files under `home`.
    public static func shortPath(_ url: URL, home: URL) -> String {
        let path = url.path
        let root = home.path.hasSuffix("/") ? String(home.path.dropLast()) : home.path
        if path == root {
            return "~"
        }
        if path.hasPrefix(root + "/") {
            return "~" + path.dropFirst(root.count)
        }
        return path
    }

    /// Scans every candidate file and replaces the stored findings for those
    /// files, so a secret that was removed disappears from the inbox.
    public static func refresh(
        store: EventStore,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        sessionCwds: [String]? = nil,
        now: Date = Date()) throws
    {
        let cwds = try sessionCwds ?? store.projects().map(\.cwd)
        let files = candidateFiles(home: home, sessionCwds: cwds)
        try store.replaceFileFindings(
            scan(files, home: home),
            for: files.map { shortPath($0, home: home) },
            at: now)
    }
}
