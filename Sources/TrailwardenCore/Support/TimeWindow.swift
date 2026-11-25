// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// `--since` values: `7d`, `12h`, `90m`, `30s`, an ISO-8601 instant, or `all`.
public enum TimeWindow {
    public enum Failure: Error, CustomStringConvertible {
        case invalid(String)

        public var description: String {
            switch self {
            case let .invalid(text): "invalid time window '\(text)' (use 7d, 12h, 90m or an ISO-8601 date)"
            }
        }
    }

    /// Returns the lower bound, or `nil` for "everything".
    public static func parse(_ text: String, now: Date = Date()) throws -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "all" || trimmed.isEmpty {
            return nil
        }

        if let unit = trimmed.last, let amount = Int(trimmed.dropLast()), amount >= 0 {
            let seconds: TimeInterval
            switch unit {
            case "s": seconds = 1
            case "m": seconds = 60
            case "h": seconds = 3600
            case "d": seconds = 86400
            case "w": seconds = 604_800
            default: throw Failure.invalid(text)
            }
            return now.addingTimeInterval(-Double(amount) * seconds)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: text) {
            return date
        }

        throw Failure.invalid(text)
    }
}
