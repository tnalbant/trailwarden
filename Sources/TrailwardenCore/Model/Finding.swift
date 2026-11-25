// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// Where a finding stands in the reader's review. A finding with no stored
/// review is `new`.
public enum ReviewState: String, Codable, Sendable, CaseIterable {
    case new
    case reviewed
    case expected
    case falsePositive
}

/// Stable identity of a finding, used by reviews and allowances.
///
/// An event finding is `event:<event_id>:<rule_id>`; a file finding is
/// `file:<path>:<rule_id>:<digest>`. Ids and paths may contain `:`, so the rule
/// id is always read from the right.
public enum FindingKey {
    public static func event(_ eventID: String, rule: String) -> String {
        "event:\(eventID):\(rule)"
    }

    public static func file(path: String, rule: String, digest: String) -> String {
        "file:\(path):\(rule):\(digest)"
    }

    public static func ruleID(of key: String) -> String? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        let candidate: Substring
        if key.hasPrefix("event:"), parts.count >= 3 {
            candidate = parts[parts.count - 1]
        } else if key.hasPrefix("file:"), parts.count >= 4 {
            candidate = parts[parts.count - 2]
        } else {
            return nil
        }
        return candidate.isEmpty ? nil : String(candidate)
    }
}
