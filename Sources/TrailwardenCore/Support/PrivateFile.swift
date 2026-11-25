// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// Writes a file that only its owner can read, from the first byte.
///
/// `Data.write(options: .atomic)` creates its temporary file with the process
/// umask (usually 0644) and a chmod afterwards leaves a moment in which an
/// export — commands, paths, findings — is readable by other accounts. This
/// writes a 0600 temporary file next to the target and renames it into place.
enum PrivateFile {
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if rename(temporary.path, url.path) != 0 {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
