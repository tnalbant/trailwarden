// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import CZstd
import Foundation

/// Streams the decompressed bytes of a `.zst` file in bounded chunks.
///
/// Codex compresses older rollouts with Zstandard. The file is never inflated
/// in memory as a whole: one compressed chunk is read, decoded into a fixed
/// output buffer, and handed on, so a 100 MB session costs a few megabytes.
/// Concatenated frames (as `zstd` writes when appending) are read in order.
enum ZstdReader {
    enum Failure: Error, CustomStringConvertible {
        case cannotAllocate
        case corrupt(String)
        case truncated

        var description: String {
            switch self {
            case .cannotAllocate: "zstd: cannot allocate a decoder"
            case let .corrupt(reason): "zstd: \(reason)"
            case .truncated: "zstd: the file ends inside a frame"
            }
        }
    }

    /// The largest window a frame may ask for: 2^27 = 128 MB, zstd's own
    /// default limit. A file that wants more is refused instead of allocated.
    static let windowLogMax: Int32 = 27

    static func forEachChunk(at url: URL, _ body: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        guard let stream = ZSTD_createDCtx() else { throw Failure.cannotAllocate }
        defer { ZSTD_freeDCtx(stream) }
        ZSTD_DCtx_setParameter(stream, ZSTD_d_windowLogMax, windowLogMax)

        let inputSize = ZSTD_DStreamInSize()
        let outputSize = ZSTD_DStreamOutSize()
        var output = [UInt8](repeating: 0, count: outputSize)
        // 0 after a completed frame, non-zero while one is still open.
        var pending = 0
        var sawInput = false

        while let chunk = try handle.read(upToCount: inputSize), !chunk.isEmpty {
            sawInput = true
            try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var input = ZSTD_inBuffer(src: raw.baseAddress, size: raw.count, pos: 0)
                while input.pos < input.size {
                    let produced = try output.withUnsafeMutableBytes { out -> Int in
                        var buffer = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                        let result = ZSTD_decompressStream(stream, &buffer, &input)
                        if ZSTD_isError(result) != 0 {
                            throw Failure.corrupt(String(cString: ZSTD_getErrorName(result)))
                        }
                        pending = result
                        return buffer.pos
                    }
                    if produced > 0 {
                        try body(Data(output[0 ..< produced]))
                    }
                }
            }
            // Flush what the decoder still holds for the data read so far.
            while pending != 0 {
                let produced = try output.withUnsafeMutableBytes { out -> Int in
                    var buffer = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    var empty = ZSTD_inBuffer(src: nil, size: 0, pos: 0)
                    let result = ZSTD_decompressStream(stream, &buffer, &empty)
                    if ZSTD_isError(result) != 0 {
                        throw Failure.corrupt(String(cString: ZSTD_getErrorName(result)))
                    }
                    pending = result
                    return buffer.pos
                }
                if produced == 0 {
                    break
                }
                try body(Data(output[0 ..< produced]))
            }
        }
        if sawInput, pending != 0 {
            throw Failure.truncated
        }
    }
}
