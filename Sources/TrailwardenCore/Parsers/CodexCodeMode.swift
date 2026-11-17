// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Newer Codex builds call their tools from a small JavaScript program instead of
/// one tool call per step:
///
///     text(await tools.exec_command({cmd:"git status --short","workdir":"/repo"}));
///     const patch = "*** Begin Patch\n*** Update File: /repo/a.py\n@@ …";
///     const r = await tools.mcp__codegraph__explore({query:"…"});
///
/// Stored as-is, the command column held JavaScript, so a `rm -rf ~` inside it was
/// invisible to every rule anchored on the start of a shell command, and the
/// timeline showed `text(await tools.exec_command({cmd:` instead of what ran.
/// This reads the program the way a person would: the shell commands it runs,
/// the files its patches touch, and the tool it calls.
///
/// It is a scanner for string literals, not a JavaScript parser. Anything it
/// cannot read leaves the event exactly as it was before.
enum CodexCodeMode {
    struct Call: Equatable {
        /// Shell commands passed to `exec_command`, in program order.
        var commands: [String] = []
        /// The `workdir` of the first `exec_command`, when it names one.
        var workdir: String?
        /// Files named by `*** Add/Update/Delete File:` and `*** Move to:` headers.
        var patchedPaths: [String] = []
        /// The tools the program calls (`exec_command`, `apply_patch`, `mcp__…`).
        var tools: [String] = []

        /// The single name the timeline should show: the shell when it runs a
        /// command, the patch tool when it only patches, else the one tool called.
        var displayTool: String? {
            if !commands.isEmpty {
                return "exec_command"
            }
            if !patchedPaths.isEmpty {
                return "apply_patch"
            }
            let meaningful = tools.filter { $0 != "write_stdin" }
            return meaningful.count == 1 ? meaningful[0] : nil
        }
    }

    /// `nil` when the text is not a code-mode program.
    static func read(_ source: String) -> Call? {
        guard source.contains("tools.") || source.contains("*** Begin Patch") else { return nil }
        var call = Call()
        call.tools = toolNames(in: source)

        var searchStart = source.startIndex
        while let range = source.range(of: "exec_command(", range: searchStart ..< source.endIndex) {
            let end = closingBrace(in: source, from: range.upperBound) ?? source.endIndex
            let argument = source[range.upperBound ..< end]
            if let command = stringValue(forKey: "cmd", in: argument), !command.isEmpty {
                call.commands.append(command)
                if call.workdir == nil {
                    call.workdir = stringValue(forKey: "workdir", in: argument)
                }
            }
            searchStart = range.upperBound
        }

        call.patchedPaths = patchHeaders(in: source)
        if call.commands.isEmpty, call.patchedPaths.isEmpty, call.tools.isEmpty {
            return nil
        }
        return call
    }

    // MARK: - Pieces

    /// `tools.<name>(` occurrences, de-duplicated in order.
    static func toolNames(in source: String) -> [String] {
        var names: [String] = []
        var searchStart = source.startIndex
        while let range = source.range(of: "tools.", range: searchStart ..< source.endIndex) {
            var index = range.upperBound
            var name = ""
            while index < source.endIndex,
                  source[index].isLetter || source[index].isNumber || source[index] == "_"
            {
                name.append(source[index])
                index = source.index(after: index)
            }
            if !name.isEmpty, index < source.endIndex, source[index] == "(", !names.contains(name) {
                names.append(name)
            }
            searchStart = range.upperBound
        }
        return names
    }

    /// The decoded string literal after `key:` (or `"key":`) inside `text`.
    static func stringValue(forKey key: String, in text: Substring) -> String? {
        for spelling in ["\"\(key)\"", "'\(key)'", key] {
            var searchStart = text.startIndex
            while let range = text.range(of: spelling, range: searchStart ..< text.endIndex) {
                searchStart = range.upperBound
                // A bare `cmd` must not be the tail of a longer identifier.
                if spelling == key, range.lowerBound > text.startIndex {
                    let before = text[text.index(before: range.lowerBound)]
                    if before.isLetter || before.isNumber || before == "_" {
                        continue
                    }
                }
                var index = range.upperBound
                skipSpaces(in: text, at: &index)
                guard index < text.endIndex, text[index] == ":" else { continue }
                index = text.index(after: index)
                skipSpaces(in: text, at: &index)
                if let literal = stringLiteral(in: text, at: index) {
                    return literal
                }
            }
        }
        return nil
    }

    /// Decodes a `"…"`, `'…'` or `` `…` `` literal starting at `index`.
    static func stringLiteral(in text: Substring, at index: Substring.Index) -> String? {
        guard index < text.endIndex else { return nil }
        let quote = text[index]
        guard quote == "\"" || quote == "'" || quote == "`" else { return nil }
        var result = ""
        var cursor = text.index(after: index)
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == quote {
                return result
            }
            if character == "\\" {
                let next = text.index(after: cursor)
                guard next < text.endIndex else { return nil }
                let escaped = text[next]
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "u":
                    let hexStart = text.index(after: next)
                    let hexEnd = text.index(hexStart, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
                    if let scalar = UInt32(text[hexStart ..< hexEnd], radix: 16)
                        .flatMap(Unicode.Scalar.init)
                    {
                        result.unicodeScalars.append(scalar)
                        cursor = hexEnd
                        continue
                    }
                    result.append("u")
                default: result.append(escaped)
                }
                cursor = text.index(after: next)
                continue
            }
            result.append(character)
            cursor = text.index(after: cursor)
        }
        return nil
    }

    /// Paths from patch headers. In the program they sit inside a string literal,
    /// so a header ends at a literal `\n`, a real newline or the closing quote.
    static func patchHeaders(in source: String) -> [String] {
        let prefixes = ["*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "]
        var paths: [String] = []
        for prefix in prefixes {
            var searchStart = source.startIndex
            while let range = source.range(of: prefix, range: searchStart ..< source.endIndex) {
                var path = ""
                var index = range.upperBound
                while index < source.endIndex {
                    let character = source[index]
                    if character == "\n" || character == "\"" || character == "'" || character == "`" {
                        break
                    }
                    if character == "\\" {
                        break
                    }
                    path.append(character)
                    index = source.index(after: index)
                }
                let trimmed = path.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !paths.contains(trimmed) {
                    paths.append(trimmed)
                }
                searchStart = range.upperBound
            }
        }
        return paths
    }

    private static func skipSpaces(in text: Substring, at index: inout Substring.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    /// The `}` that closes the object literal opened right after `from`, skipping
    /// braces inside string literals. `nil` when the program is cut short.
    static func closingBrace(in source: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var index = start
        var quote: Character?
        while index < source.endIndex {
            let character = source[index]
            if let open = quote {
                if character == "\\" {
                    index = source.index(after: index)
                    if index < source.endIndex {
                        index = source.index(after: index)
                    }
                    continue
                }
                if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" || character == "`" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return source.index(after: index)
                }
            } else if character == ")", depth == 0 {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }
}
