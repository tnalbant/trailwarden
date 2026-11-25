// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// Onboarding: what the app will read.
extension AppModel {
    /// What the app will read, with a live count per transcript root. Agents
    /// that keep one history database count as one file.
    static func transcriptRoots() -> [TranscriptRoot] {
        let folders = ScanRoot.standard().map { root in
            let exists = FileManager.default.fileExists(atPath: root.directory.path)
            return TranscriptRoot(
                agent: root.agent,
                path: root.directory.path,
                files: exists ? countTranscripts(in: root) : 0,
                exists: exists)
        }
        let databases = ScanRoot.standardDatabases().map { source in
            let exists = FileManager.default.fileExists(atPath: source.database.path)
            return TranscriptRoot(
                agent: source.agent,
                path: source.database.path,
                files: exists ? 1 : 0,
                exists: exists)
        }
        return folders + databases
    }

    private static func countTranscripts(in root: ScanRoot) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root.directory,
            includingPropertiesForKeys: nil)
        else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where root.parser.accepts(url) {
            count += 1
        }
        return count
    }
}
