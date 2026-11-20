// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Loads the built-in rule set and merges user overrides on top of it.
public enum RuleCatalog {
    /// Rules compiled into the binary (`BuiltInRules`, generated from
    /// `Resources/rules.json`). No resource bundle is involved, so a tool copied
    /// on its own — by Homebrew, npm or `make install` — still has its rules.
    public static func builtIn() throws -> [Rule] {
        try decode(Data(BuiltInRules.json.utf8))
    }

    public static func load(from url: URL) throws -> [Rule] {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> [Rule] {
        try JSONDecoder().decode([Rule].self, from: data)
    }

    /// A user file replaces built-ins with the same id (so a rule can be turned
    /// off or re-graded) and appends rules the built-ins do not know.
    public static func merge(builtIn: [Rule], overrides: [Rule]) -> [Rule] {
        var byId = Dictionary(overrides.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var merged: [Rule] = []
        for rule in builtIn {
            if let override = byId.removeValue(forKey: rule.id) {
                merged.append(override)
            } else {
                merged.append(rule)
            }
        }
        merged.append(contentsOf: byId.values.sorted { $0.id < $1.id })
        return merged
    }
}
