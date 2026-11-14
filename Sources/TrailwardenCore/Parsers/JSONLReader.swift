// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Streams a JSONL file line by line without loading it into memory.
///
/// Transcript files routinely grow past 100 MB, so the reader works on fixed
/// size chunks and only keeps the unfinished tail between reads. Line numbers
/// are physical (blank lines included) because event ids are derived from them.
enum JSONLReader {
    static let chunkSize = 1 << 20

    static func forEachLine(at url: URL, _ body: (Int, String) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        var lineNumber = 0

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)

            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 0x0A) {
                lineNumber += 1
                try body(lineNumber, String(decoding: buffer[start..<newline], as: UTF8.self))
                start = buffer.index(after: newline)
            }

            if start > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<start)
            }
        }

        if !buffer.isEmpty {
            lineNumber += 1
            try body(lineNumber, String(decoding: buffer, as: UTF8.self))
        }
    }
}
