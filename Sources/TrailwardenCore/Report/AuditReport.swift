// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Everything the report needs to describe itself. Passed in explicitly so a
/// report is reproducible: the same data and selection always render the same
/// bytes, which is what the golden tests check.
public struct AuditSelection: Sendable {
    public var since: Date?
    public var until: Date
    public var agents: [Agent]
    public var minimumSeverity: Severity?
    public var generatedAt: Date

    public init(
        since: Date?,
        until: Date,
        agents: [Agent] = [],
        minimumSeverity: Severity? = nil,
        generatedAt: Date = Date())
    {
        self.since = since
        self.until = until
        self.agents = agents.sorted { $0.rawValue < $1.rawValue }
        self.minimumSeverity = minimumSeverity
        self.generatedAt = generatedAt
    }
}

public struct AuditSummary: Sendable, Equatable {
    public var sessions = 0
    public var events = 0
    public var findings = 0
    public var critical = 0
    public var warn = 0
    public var info = 0
}

public enum AuditReport {
    public static func summarize(sessions: [SessionSummary], events: [Event]) -> AuditSummary {
        var summary = AuditSummary()
        summary.sessions = sessions.count
        summary.events = events.count
        for event in events where !event.risk.isEmpty {
            summary.findings += 1
            if let worst = event.risk.map(\.severity).max() {
                switch worst {
                case .critical: summary.critical += 1
                case .warn: summary.warn += 1
                case .info: summary.info += 1
                }
            }
        }
        return summary
    }

    /// Hit counts per rule, ordered as R1, R2, R10.
    public static func ruleCounts(events: [Event]) -> [(ruleId: String, severity: Severity, hits: Int)] {
        var severities: [String: Severity] = [:]
        var counts: [String: Int] = [:]
        for event in events {
            for hit in event.risk {
                counts[hit.ruleId, default: 0] += 1
                severities[hit.ruleId] = max(severities[hit.ruleId] ?? hit.severity, hit.severity)
            }
        }
        return counts.keys
            .sorted { ruleNumber($0) < ruleNumber($1) }
            .map { (ruleId: $0, severity: severities[$0] ?? .info, hits: counts[$0] ?? 0) }
    }

    static func ruleNumber(_ id: String) -> Int {
        Int(id.drop(while: { !$0.isNumber })) ?? Int.max
    }
}

// MARK: - Markdown

public enum MarkdownReport {
    public static func render(
        sessions: [SessionSummary],
        events: [Event],
        selection: AuditSelection) -> String
    {
        let summary = AuditReport.summarize(sessions: sessions, events: events)
        let orderedSessions = sessions.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
        let orderedEvents = ordered(events: events)
        let findings = orderedEvents.filter { !$0.risk.isEmpty }

        var lines: [String] = []
        lines.append("# Trailwarden audit record")
        lines.append("")
        lines.append("| | |")
        lines.append("|---|---|")
        lines.append("| Generated | \(timestamp(selection.generatedAt)) |")
        lines.append("| Window | \(windowText(selection)) |")
        lines.append("| Agents | \(agentsText(selection)) |")
        lines.append("| Minimum severity | \(selection.minimumSeverity?.rawValue ?? "any finding") |")
        lines.append("")

        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|---|---|")
        lines.append("| Sessions | \(summary.sessions) |")
        lines.append("| Events | \(summary.events) |")
        lines.append("| Findings | \(summary.findings) |")
        lines.append("| Critical | \(summary.critical) |")
        lines.append("| Warn | \(summary.warn) |")
        lines.append("| Info | \(summary.info) |")
        lines.append("")

        if !orderedSessions.isEmpty {
            lines.append("## Sessions")
            lines.append("")
            lines.append("| Session | Agent | Project | Started (UTC) | Events | Critical |")
            lines.append("|---|---|---|---|---|---|")
            for session in orderedSessions {
                let id = shortID(session.id)
                let project = session.cwd.map(shorten) ?? "-"
                lines.append(
                    "| \(cell(id)) | \(session.agent.rawValue) | \(cell(project)) | "
                        +
                        "\(timestamp(session.startedAt)) | \(session.eventCount) | \(session.criticalCount) |")
            }
            lines.append("")
        }

        lines.append("## Findings")
        lines.append("")
        if findings.isEmpty {
            lines.append("No findings in this window.")
        } else {
            lines.append("| Time (UTC) | Agent | Tool | Rule | Severity | Detail |")
            lines.append("|---|---|---|---|---|---|")
            for event in findings {
                for hit in event.risk.sorted(by: { $0.severity > $1.severity }) {
                    let detail = event.command ?? event.preview ?? hit.message
                    lines.append(
                        "| \(timestamp(event.ts)) | \(event.agent.rawValue) | \(cell(event.tool ?? "-")) | "
                            + "\(hit.ruleId) | \(hit.severity.rawValue) | \(cell(detail, limit: 80)) |")
                }
            }
        }
        lines.append("")

        let counts = AuditReport.ruleCounts(events: orderedEvents)
        lines.append("## Risk summary")
        lines.append("")
        if counts.isEmpty {
            lines.append("No rules matched.")
        } else {
            lines.append("| Rule | Severity | Hits |")
            lines.append("|---|---|---|")
            for entry in counts {
                lines.append("| \(entry.ruleId) | \(entry.severity.rawValue) | \(entry.hits) |")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting helpers

    private static func ordered(events: [Event]) -> [Event] {
        events.sorted { lhs, rhs in
            lhs.ts == rhs.ts ? lhs.id < rhs.id : lhs.ts > rhs.ts
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func windowText(_ selection: AuditSelection) -> String {
        let end = timestamp(selection.until)
        guard let since = selection.since else { return "everything up to \(end)" }
        return "\(timestamp(since)) to \(end)"
    }

    private static func agentsText(_ selection: AuditSelection) -> String {
        selection.agents.isEmpty ? "all" : selection.agents.map(\.rawValue).joined(separator: ", ")
    }

    /// Time-ordered session ids share their first bytes, so a bare prefix is not
    /// unique; keep the head and the tail.
    static func shortID(_ id: String) -> String {
        guard id.count > 12 else { return id }
        return String(id.prefix(8)) + "…" + String(id.suffix(4))
    }

    private static func shorten(_ path: String) -> String {
        Redactor().shortenHome(path)
    }

    /// Table cells cannot contain a pipe or a newline.
    static func cell(_ text: String, limit: Int = 60) -> String {
        var value = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        if value.count > limit {
            value = String(value.prefix(limit)) + "…"
        }
        return value
    }
}

// MARK: - JSON

public enum JSONReport {
    public struct Document: Encodable {
        public let schema: Int
        public let generatedAt: Date
        public let window: Window
        public let agents: [String]
        public let minimumSeverity: String?
        public let summary: Summary
        public let sessions: [SessionRow]
        public let events: [EventRow]

        public struct Window: Encodable {
            public let since: Date?
            public let until: Date
        }

        public struct Summary: Encodable {
            public let sessions: Int
            public let events: Int
            public let findings: Int
            public let critical: Int
            public let warn: Int
            public let info: Int
        }

        public struct SessionRow: Encodable {
            public let id: String
            public let agent: String
            public let cwd: String?
            public let gitBranch: String?
            public let startedAt: Date
            public let endedAt: Date
            public let eventCount: Int
            public let criticalCount: Int
        }

        public struct EventRow: Encodable {
            public let id: String
            public let ts: Date
            public let agent: String
            public let sessionId: String
            public let kind: String
            public let cwd: String?
            public let gitBranch: String?
            public let tool: String?
            public let command: String?
            public let paths: [String]
            public let preview: String?
            public let risk: [RiskRow]

            public struct RiskRow: Encodable {
                public let ruleId: String
                public let severity: String
                public let message: String
            }
        }
    }

    public static func makeDocument(
        sessions: [SessionSummary],
        events: [Event],
        selection: AuditSelection,
        redactor: Redactor = Redactor(level: .normal)) -> Document
    {
        let summary = AuditReport.summarize(sessions: sessions, events: events)
        let orderedSessions = sessions.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
        let orderedEvents = events.sorted { lhs, rhs in
            lhs.ts == rhs.ts ? lhs.id < rhs.id : lhs.ts > rhs.ts
        }

        return Document(
            schema: TrailwardenVersion.schema,
            generatedAt: selection.generatedAt,
            window: .init(since: selection.since, until: selection.until),
            agents: selection.agents.isEmpty ? Agent.allCases.map(\.rawValue) : selection.agents
                .map(\.rawValue),
            minimumSeverity: selection.minimumSeverity?.rawValue,
            summary: .init(
                sessions: summary.sessions,
                events: summary.events,
                findings: summary.findings,
                critical: summary.critical,
                warn: summary.warn,
                info: summary.info),
            sessions: orderedSessions.map {
                .init(
                    id: $0.id,
                    agent: $0.agent.rawValue,
                    cwd: $0.cwd.map { redactor.shortenHome($0) },
                    gitBranch: $0.gitBranch,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    eventCount: $0.eventCount,
                    criticalCount: $0.criticalCount)
            },
            events: orderedEvents.map { event in
                let safe = redactor.redactForExport(event)
                return .init(
                    id: safe.id,
                    ts: safe.ts,
                    agent: safe.agent.rawValue,
                    sessionId: safe.sessionId,
                    kind: safe.kind.rawValue,
                    cwd: safe.cwd,
                    gitBranch: safe.gitBranch,
                    tool: safe.tool,
                    command: safe.command,
                    paths: safe.paths,
                    preview: safe.preview,
                    risk: safe.risk.map {
                        .init(ruleId: $0.ruleId, severity: $0.severity.rawValue, message: $0.message)
                    })
            })
    }

    public static func data(
        sessions: [SessionSummary],
        events: [Event],
        selection: AuditSelection,
        redactor: Redactor = Redactor(level: .normal)) throws -> Data
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(
            makeDocument(sessions: sessions, events: events, selection: selection, redactor: redactor))
    }
}
