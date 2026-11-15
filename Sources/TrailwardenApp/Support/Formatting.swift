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
        }
    }
}
