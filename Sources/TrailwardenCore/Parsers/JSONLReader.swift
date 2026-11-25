// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// Streams a JSONL file line by line without loading it into memory.
///
/// Transcript files routinely grow past 100 MB, so the reader works on fixed
/// size chunks and only keeps the unfinished tail between reads. Line numbers
/// are physical (blank lines included) because event ids are derived from them.
/// A `.zst` file yields the same lines, in the same order, as its plain copy.
enum JSONLReader {
    static let chunkSize = 1 << 20

    /// `name.jsonl.zst` is read through the zstd decoder; everything else as is.
    static func isCompressed(_ url: URL) -> Bool {
        url.pathExtension == "zst"
    }

    static func forEachLine(at url: URL, _ body: (Int, String) throws -> Void) throws {
        var buffer = Data()
        var lineNumber = 0
        // Bytes of `buffer` already searched for a newline. A line of several
        // megabytes arrives over many chunks; without this every chunk would
        // search the whole unfinished line again.
        var searched = 0

        func consume(_ chunk: Data) throws {
            buffer.append(chunk)

            var lines: [Range<Int>] = []
            buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                var start = 0
                var from = searched
                while from < raw.count,
                      let hit = memchr(base + from, 0x0A, raw.count - from)
                {
                    let newline = base.distance(to: UnsafeRawPointer(hit))
                    lines.append(start ..< newline)
                    start = newline + 1
                    from = start
                }
                searched = raw.count
            }

            let origin = buffer.startIndex
            for range in lines {
                lineNumber += 1
                let slice = buffer[(origin + range.lowerBound) ..< (origin + range.upperBound)]
                try body(lineNumber, String(decoding: slice, as: UTF8.self))
            }

            if let last = lines.last {
                buffer.removeSubrange(origin ..< (origin + last.upperBound + 1))
                searched -= last.upperBound + 1
            }
        }

        if isCompressed(url) {
            try ZstdReader.forEachChunk(at: url, consume)
        } else {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                try consume(chunk)
            }
        }

        if !buffer.isEmpty {
            lineNumber += 1
            try body(lineNumber, String(decoding: buffer, as: UTF8.self))
        }
    }
}
