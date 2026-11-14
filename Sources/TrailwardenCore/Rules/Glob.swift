// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Minimal glob matcher: `*` stays inside one path component, `**` crosses
/// components, `?` is one character. Matching is always anchored, so a glob never
/// matches a random substring of a command.
enum Glob {
    static func regex(for pattern: String) -> NSRegularExpression? {
        var output = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            switch character {
            case "*":
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    let after = pattern.index(after: next)
                    if after < pattern.endIndex, pattern[after] == "/" {
                        // "**/" matches zero or more leading directories.
                        output += "(?:.*/)?"
                        index = pattern.index(after: after)
                    } else {
                        output += ".*"
                        index = after
                    }
                } else {
                    output += "[^/]*"
                    index = next
                }
            case "?":
                output += "[^/]"
                index = pattern.index(after: index)
            default:
                output += NSRegularExpression.escapedPattern(for: String(character))
                index = pattern.index(after: index)
            }
        }
        output += "$"
        return try? NSRegularExpression(pattern: output)
    }

    static func matches(_ regex: NSRegularExpression, _ candidate: String) -> Bool {
        let range = NSRange(candidate.startIndex..., in: candidate)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }
}
