// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

extension TranscriptArchive {
    /// The archive next to the index, or nil while the setting is off.
    static func ifEnabled(databaseURL: URL, store: EventStore) -> TranscriptArchive? {
        guard UserDefaults.standard.bool(forKey: ArchiveSetting.enabledKey) else { return nil }
        let root = databaseURL.deletingLastPathComponent().appendingPathComponent(
            "Archive",
            isDirectory: true)
        return TranscriptArchive(root: root, store: store)
    }
}
