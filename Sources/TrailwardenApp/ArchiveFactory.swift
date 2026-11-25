// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation
import TrailwardenCore

extension TranscriptArchive {
    /// The archive next to the index, or nil while the setting is off.
    static func ifEnabled(databaseURL: URL, store: EventStore) -> TranscriptArchive? {
        guard UserDefaults.standard.bool(forKey: ArchiveSetting.enabledKey) else { return nil }
        return TranscriptArchive(root: archiveRoot(databaseURL: databaseURL), store: store)
    }

    /// Where full copies live: an `Archive` folder next to the index.
    static func archiveRoot(databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent("Archive", isDirectory: true)
    }
}
