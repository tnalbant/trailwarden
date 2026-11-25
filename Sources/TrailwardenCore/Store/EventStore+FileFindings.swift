// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

public extension EventStore {
    /// Replaces the stored file findings of `paths` (home-shortened) with
    /// `findings`. Findings that were already stored keep their first-seen time.
    /// Reviews of keys that vanish are left; the orphan clean-up removes them.
    func replaceFileFindings(_ findings: [FileFinding], for paths: [String], at: Date = Date()) throws {
        let earlier = try database.prepare("SELECT found_at FROM file_findings WHERE finding_key = ?")
        var firstSeen: [String: Double] = [:]
        for finding in findings {
            try earlier.bind([.text(finding.key)])
            if try earlier.step(), let value = earlier.double(0) {
                firstSeen[finding.key] = value
            }
        }
        let delete = try database.prepare("DELETE FROM file_findings WHERE path = ?")
        let insert = try database.prepare("""
        INSERT OR REPLACE INTO file_findings
        (finding_key, path, rule_id, severity, line, preview, found_at) VALUES (?,?,?,?,?,?,?)
        """)
        try database.transaction {
            for path in Set(paths) {
                try delete.bind([.text(path)])
                try delete.step()
            }
            for finding in findings {
                try insert.bind([
                    .text(finding.key), .text(finding.path), .text(finding.ruleId),
                    .text(finding.severity.rawValue), .int(finding.line), .text(finding.preview),
                    .double(firstSeen[finding.key] ?? at.timeIntervalSince1970)
                ])
                try insert.step()
            }
        }
    }

    /// Deletes stored file findings whose path is not in `paths`.
    func removeFileFindings(notIn paths: [String]) throws {
        let known = Set(paths)
        let select = try database.prepare("SELECT DISTINCT path FROM file_findings")
        var stale: [String] = []
        while try select.step() {
            if let path = select.text(0), !known.contains(path) {
                stale.append(path)
            }
        }
        let delete = try database.prepare("DELETE FROM file_findings WHERE path = ?")
        for path in stale {
            try delete.bind([.text(path)])
            try delete.step()
        }
    }
}
