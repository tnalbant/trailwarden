// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// `cd ~/.aws && cat credentials`: the folder a command line changed into.
extension RuleEngine {
    /// Folders whose files are secret by their place: a command that runs after
    /// `cd` into one of them reads files by relative name.
    private static let secretDirectories: [NSRegularExpression] = [
        "**/.ssh", "**/.ssh/**", "**/.aws", "**/.aws/**", "**/.gnupg", "**/.gnupg/**",
        "**/.config/gh", "**/.config/gh/**", "**/.kube", "**/.kube/**",
        "**/.docker", "**/.docker/**"
    ].compactMap { Glob.regex(for: normalizeGlob($0)) }

    static func isSecretDirectory(_ directory: String) -> Bool {
        secretDirectories.contains { Glob.matches($0, directory) }
    }

    private static let changeDirectory = try? NSRegularExpression(
        pattern: #"^\s*[({]?\s*(?:pushd|cd)\b"#)

    /// The folders in force after one command: a `cd`/`pushd` to an absolute or
    /// `~` path replaces them, a relative one is joined to them (or stands alone
    /// when none is known), `cd ..` keeps them (it may still be inside, which
    /// errs on the side of flagging) and `cd -` clears them; any other command
    /// leaves them alone.
    static func directoriesAfter(_ body: String, previous: [String]) -> [String] {
        guard let changeDirectory,
              changeDirectory.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
        else { return previous }
        // A brace group or subshell glues its bracket to the first word.
        let words = tokens(in: body)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "({})")) }
            .filter { !$0.isEmpty }
        let targets = words.drop { $0 != "cd" && $0 != "pushd" }.dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map(normalizePathToken).filter { !$0.isEmpty }
        guard let target = targets.first else { return [] }
        if target.hasPrefix("/") || target.hasPrefix("~") || target.hasPrefix("$") {
            return [target]
        }
        if target == ".." {
            return previous
        }
        if previous.isEmpty {
            return [target]
        }
        return previous.map { ($0.hasSuffix("/") ? $0 : $0 + "/") + target }
    }
}
