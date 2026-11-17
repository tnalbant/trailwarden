// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Picking up where a session stopped is the one action a history browser is
/// asked for most often. Each agent spells it differently, so the exact command
/// lives here, in one place, and the UI only copies it.
public enum ResumeCommand {
    public static func command(agent: Agent, sessionId: String, cwd: String?) -> String? {
        guard !sessionId.isEmpty else { return nil }

        let changeDirectory = if let cwd, !cwd.isEmpty {
            "cd \(quoted(cwd)) && "
        } else {
            ""
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
        case .cursor, .copilot:
            // Cursor chats live in the editor, and Copilot's resume flag could
            // not be verified on a machine with the app; no command is better
            // than a wrong one.
            return nil
        }
    }

    /// Single quotes, with the one escape a POSIX shell needs.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
