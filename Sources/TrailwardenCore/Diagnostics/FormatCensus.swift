// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Counts the record types and top-level key names in transcript files, so a
/// new agent version's format can be checked without reading anyone's text.
/// Only names are counted, never values.
public enum FormatCensus {
    public static func census(of files: [URL], agent _: Agent) -> [String: Int] {
        var counts: [String: Int] = [:]
        for file in files {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            if file.pathExtension == "jsonl" {
                for line in data.split(separator: UInt8(ascii: "\n")) {
                    record(Data(line), into: &counts)
                }
            } else {
                record(data, into: &counts)
            }
        }
        return counts
    }

    /// One line per entry, sorted, for `doctor --formats`.
    public static func text(_ census: [String: Int]) -> String {
        census.sorted { $0.key < $1.key }
            .map { "  \($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private static func record(_ data: Data, into counts: inout [String: Int]) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for key in object.keys {
            counts["key=\(key)", default: 0] += 1
        }
        if let type = object["type"] as? String {
            counts["type=\(type)", default: 0] += 1
        }
    }
}
