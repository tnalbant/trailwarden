// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Picking up where a session stopped is the one action a history browser is
/// asked for most often. Each agent spells it differently, so the exact command
/// lives here, in one place, and the UI only copies it.
public enum ResumeCommand {
    public static func command(agent: Agent, sessionId: String, cwd: String?) -> String? {
        guard !sessionId.isEmpty else { return nil }

        let changeDirectory: String
        if let cwd, !cwd.isEmpty {
            changeDirectory = "cd \(quoted(cwd)) && "
        } else {
            changeDirectory = ""
        }

        switch agent {
        case .claudeCode:
            return "\(changeDirectory)claude --resume \(sessionId)"
        case .codex:
            return "\(changeDirectory)codex resume \(sessionId)"
        case .gemini:
            return "\(changeDirectory)gemini --resume \(sessionId)"
        case .opencode:
            return "\(changeDirectory)opencode --session \(sessionId)"
        case .hermes:
            return "\(changeDirectory)hermes --resume \(sessionId)"
        }
    }

    /// Single quotes, with the one escape a POSIX shell needs.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
