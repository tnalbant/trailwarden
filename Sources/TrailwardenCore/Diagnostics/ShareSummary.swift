// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// A block of counts a reader can paste into a bug report. It carries versions
/// and numbers only: no paths, commands, previews, session ids or names.
public enum ShareSummary {
    public static func text(store: EventStore, version: String, osVersion: String) throws -> String {
        var lines = try [
            "Trailwarden \(version)",
            "macOS \(osVersion)",
            "schema \(store.schemaVersion())",
            "rules \(RuleCatalog.builtIn().count)"
        ]

        lines.append("events per agent:")
        for agent in Agent.allCases {
            let count = try store.eventCount(matching: EventQuery(agents: [agent]))
            if count > 0 {
                lines.append("  \(agent.rawValue): \(count)")
            }
        }

        let counts = try store.falsePositiveCounts().filter { isRuleID($0.key) }
        lines.append("false alarms per rule:")
        for (rule, count) in counts.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(rule): \(count)")
        }
        return lines.joined(separator: "\n")
    }

    /// Rule ids are short tokens; anything else is not printed.
    private static func isRuleID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 32
            && text.unicodeScalars
            .allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }
}
