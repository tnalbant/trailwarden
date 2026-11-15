// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Which coding agent produced an event.
public enum Agent: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
    case opencode
    case gemini
    case hermes
}

/// What kind of thing happened inside a session.
public enum EventKind: String, Codable, Sendable, CaseIterable {
    case sessionStart = "session_start"
    case message
    case reasoning
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case fileChange = "file_change"
    case permission
    case tokenUsage = "token_usage"
}

/// How much attention a rule hit deserves.
public enum Severity: String, Codable, Sendable, Comparable, CaseIterable {
    case info
    case warn
    case critical

    /// Ordering used by filters (`--severity warn` means warn or critical).
    public var rank: Int {
        switch self {
        case .info: 0
        case .warn: 1
        case .critical: 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One rule match attached to an event.
public struct RiskHit: Codable, Sendable, Hashable {
    public let ruleId: String
    public let severity: Severity
    public let message: String

    public init(ruleId: String, severity: Severity, message: String) {
        self.ruleId = ruleId
        self.severity = severity
        self.message = message
    }
}

/// A single normalized event from an agent transcript.
///
/// `rawJSON` is the source line, kept for the "raw data" view. It is masked
/// before it is stored or exported — "raw" never means "unredacted".
public struct Event: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let ts: Date
    public let agent: Agent
    public let sessionId: String
    public let kind: EventKind
    public let cwd: String?
    public let gitBranch: String?
    public let tool: String?
    public let command: String?
    public let paths: [String]
    public let preview: String?
    public let risk: [RiskHit]
    public let rawJSON: String?

    public init(
        id: String,
        ts: Date,
        agent: Agent,
        sessionId: String,
        kind: EventKind,
        cwd: String? = nil,
        gitBranch: String? = nil,
        tool: String? = nil,
        command: String? = nil,
        paths: [String] = [],
        preview: String? = nil,
        risk: [RiskHit] = [],
        rawJSON: String? = nil)
    {
        self.id = id
        self.ts = ts
        self.agent = agent
        self.sessionId = sessionId
        self.kind = kind
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.tool = tool
        self.command = command
        self.paths = paths
        self.preview = preview
        self.risk = risk
        self.rawJSON = rawJSON
    }

    /// A copy carrying fresh rule hits (the parser always produces an empty list).
    public func withRisk(_ risk: [RiskHit]) -> Event {
        Event(
            id: id,
            ts: ts,
            agent: agent,
            sessionId: sessionId,
            kind: kind,
            cwd: cwd,
            gitBranch: gitBranch,
            tool: tool,
            command: command,
            paths: paths,
            preview: preview,
            risk: risk,
            rawJSON: rawJSON)
    }

    /// A copy that knows which folder it happened in, when the agent did not
    /// record one itself.
    public func withCwd(_ cwd: String) -> Event {
        Event(
            id: id,
            ts: ts,
            agent: agent,
            sessionId: sessionId,
            kind: kind,
            cwd: cwd,
            gitBranch: gitBranch,
            tool: tool,
            command: command,
            paths: paths,
            preview: preview,
            risk: risk,
            rawJSON: rawJSON)
    }

    /// Stable identity for an event: the same transcript parsed twice yields
    /// the same ids, and two events on the same line still differ (`index`).
    static func makeID(
        agent: Agent,
        sessionId: String,
        source: String,
        line: Int,
        index: Int) -> String
    {
        let material = "\(agent.rawValue)|\(sessionId)|\(source)|\(line):\(index)"
        let digest = SHA256Hasher.hash(Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
