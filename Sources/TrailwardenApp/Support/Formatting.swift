// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// Path and id formatting shared by the timeline views.
enum ProjectName {
    /// Last path component, with the home directory written as `~`.
    static func short(_ path: String) -> String {
        let shortened = path.hasPrefix(NSHomeDirectory())
            ? "~" + path.dropFirst(NSHomeDirectory().count)
            : path
        return shortened.split(separator: "/").last.map(String.init) ?? shortened
    }

    static func display(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory())
            ? "~" + path.dropFirst(NSHomeDirectory().count)
            : path
    }
}

enum Sessions {
    /// Session ids encode a timestamp in their leading bytes, so a bare prefix is
    /// not unique; keep the head and the tail.
    static func shortID(_ id: String) -> String {
        guard id.count > 12 else { return id }
        return String(id.prefix(8)) + "…" + String(id.suffix(4))
    }
}

enum EventFormatting {
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    /// A row stamp that says which day when the day is not today. The rule lives
    /// in Core so it can be tested without a window.
    static func stamp(_ date: Date) -> String {
        ActivityDigest.stamp(date, locale: LocalizationStore.current.locale)
    }

    /// "5m", "1h 20m"; `nil` for a session that lasted under a second.
    static func duration(from start: Date, to end: Date) -> String? {
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 1 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds < 60 ? [.second] : [.day, .hour, .minute]
        var calendar = Calendar.current
        calendar.locale = LocalizationStore.current.locale
        formatter.calendar = calendar
        return formatter.string(from: seconds)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = LocalizationStore.current.locale
        return formatter.string(from: date)
    }

    static func agentLabel(_ agent: Agent) -> String {
        switch agent {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .opencode: "opencode"
        case .gemini: "gemini"
        case .hermes: "hermes"
        case .cursor: "cursor"
        case .copilot: "copilot"
        }
    }
}
