// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// One line of a diff, classified for the coloured view.
public struct DiffLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case header // @@ hunk marker, *** Update File
        case addition
        case removal
        case context
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Pulls a diff out of a tool call. Agents emit two shapes here: unified diffs
/// (`@@` hunks, `+`/`-` lines) and codex's patch format (`*** Begin Patch`,
/// `*** Update File:`). Shell commands are full of leading dashes, so a text only
/// counts as a diff when it has a real marker — a hunk header, the patch
/// sentinel, or at least three changed lines in a row.
public enum DiffExtractor {
    public static func diff(in text: String) -> [DiffLine]? {
        let lines = (patchPayload(in: text) ?? text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard !lines.isEmpty else { return nil }

        let hasMarker = lines.contains { line in
            line.hasPrefix("@@") || line.hasPrefix("*** Begin Patch") || line.hasPrefix("*** Update File:")
        }
        let changedRuns = longestChangedRun(in: lines)
        guard hasMarker || changedRuns >= 3 else { return nil }

        return lines.map { line in
            if line.hasPrefix("@@") || line.hasPrefix("*** ")
                || line.hasPrefix("+++") || line.hasPrefix("---")
                || line.hasPrefix("diff ") || line.hasPrefix("index ")
            {
                return DiffLine(kind: .header, text: line)
            }
            if line.hasPrefix("+") {
                return DiffLine(kind: .addition, text: String(line.dropFirst()))
            }
            if line.hasPrefix("-") {
                return DiffLine(kind: .removal, text: String(line.dropFirst()))
            }
            return DiffLine(kind: .context, text: line)
        }
    }

    /// Codex wraps the patch in a JavaScript call:
    /// `const patch = "*** Begin Patch\n*** Update File: …\n+…";\ntext(await tools.apply_patch(patch));`
    /// so the newlines arrive escaped. Everything from the sentinel to `*** End
    /// Patch` is the real payload; unescape it before splitting into lines.
    private static func patchPayload(in text: String) -> String? {
        guard let start = text.range(of: "*** Begin Patch") else { return nil }
        let tail = text[start.lowerBound...]
        let body: Substring = if let end = tail.range(of: "*** End Patch") {
            tail[tail.startIndex ..< end.upperBound]
        } else {
            tail
        }
        return String(body)
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    /// Longest streak of consecutive added or removed lines, ignoring blank rows.
    private static func longestChangedRun(in lines: [String]) -> Int {
        var best = 0
        var current = 0
        for line in lines {
            let changed = (line.hasPrefix("+") && !line.hasPrefix("+++"))
                || (line.hasPrefix("-") && !line.hasPrefix("---"))
            if changed {
                current += 1
                best = max(best, current)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                current = 0
            }
        }
        return best
    }
}
