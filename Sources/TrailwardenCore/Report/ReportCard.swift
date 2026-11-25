// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// "What did my agents do this month?" in one screen: how much work, by whom,
/// what changed, and the few things worth a second look.
///
/// It is the first thing a new reader sees after the first scan, so it answers
/// with sentences and a short list rather than a table of counters.
public struct ReportCard: Sendable, Equatable {
    public struct AgentShare: Sendable, Equatable, Identifiable {
        public let agent: Agent
        public let toolCalls: Int
        public let sessions: Int

        public var id: String {
            agent.rawValue
        }
    }

    public struct HotFile: Sendable, Equatable, Identifiable {
        public let path: String
        public let changes: Int
        public let agents: [Agent]

        public var id: String {
            path
        }
    }

    public struct RuleCount: Sendable, Equatable, Identifiable {
        public let ruleId: String
        public let severity: Severity
        public let count: Int

        public var id: String {
            ruleId
        }
    }

    public let since: Date
    public let until: Date
    public var toolCalls = 0
    public var commands = 0
    public var edits = 0
    public var reads = 0
    public var sessions = 0
    public var projects = 0
    public var filesChanged = 0
    public var critical = 0
    public var warnings = 0
    public var agents: [AgentShare] = []
    public var hotFiles: [HotFile] = []
    public var rules: [RuleCount] = []
    /// The findings to look at first: critical before warning, newest first.
    public var worthALook: [Event] = []

    public var isEmpty: Bool {
        toolCalls == 0
    }

    public init(since: Date, until: Date) {
        self.since = since
        self.until = until
    }

    /// Builds the card from tool calls in `[since, until]`.
    public static func build(
        from store: EventStore,
        days: Int = 30,
        now: Date = Date(),
        findingLimit: Int = 6) throws -> ReportCard
    {
        let since = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(days - 1) * 86400))
        var query = EventQuery(since: since, until: now)
        query.includeRawJSON = false
        query.excludedKinds = Set(EventKind.allCases).subtracting([.toolCall])
        return try build(
            from: store.events(matching: query),
            since: since,
            until: now,
            findingLimit: findingLimit)
    }

    /// The same card from events already loaded; what the tests drive.
    public static func build(
        from events: [Event],
        since: Date,
        until: Date,
        findingLimit: Int = 6) -> ReportCard
    {
        var card = ReportCard(since: since, until: until)
        var sessionsByAgent: [Agent: Set<String>] = [:]
        var callsByAgent: [Agent: Int] = [:]
        var allSessions = Set<String>()
        var projects = Set<String>()
        var changes: [String: (count: Int, agents: Set<Agent>)] = [:]
        var ruleCounts: [String: (Severity, Int)] = [:]
        var findings: [Event] = []

        for event in events where event.kind == .toolCall {
            card.toolCalls += 1
            callsByAgent[event.agent, default: 0] += 1
            sessionsByAgent[event.agent, default: []].insert(event.sessionId)
            allSessions.insert(event.sessionId)
            if let cwd = event.cwd, !cwd.isEmpty {
                projects.insert(cwd)
            }

            switch RuleEngine.canonicalTool(event.tool) {
            case "Bash":
                card.commands += 1
            case "Write", "Edit":
                card.edits += 1
                for path in event.paths {
                    let key = absolute(path, cwd: event.cwd)
                    var entry = changes[key] ?? (0, [])
                    entry.count += 1
                    entry.agents.insert(event.agent)
                    changes[key] = entry
                }
            case "Read":
                card.reads += 1
            default:
                break
            }

            guard let worst = event.activeRisk.map(\.severity).max() else { continue }
            switch worst {
            case .critical: card.critical += 1
            case .warn: card.warnings += 1
            case .info: break
            }
            if worst >= .warn {
                findings.append(event)
            }
            for hit in event.activeRisk {
                let current = ruleCounts[hit.ruleId] ?? (hit.severity, 0)
                ruleCounts[hit.ruleId] = (max(current.0, hit.severity), current.1 + 1)
            }
        }

        card.sessions = allSessions.count
        card.projects = projects.count
        card.filesChanged = changes.count
        card.agents = callsByAgent.map { agent, calls in
            AgentShare(agent: agent, toolCalls: calls, sessions: sessionsByAgent[agent]?.count ?? 0)
        }
        card.agents.sort { lhs, rhs in
            lhs.toolCalls == rhs.toolCalls ? lhs.agent.rawValue < rhs.agent.rawValue : lhs.toolCalls > rhs
                .toolCalls
        }
        var files: [HotFile] = changes.map { path, entry in
            HotFile(
                path: path,
                changes: entry.count,
                agents: entry.agents.sorted { $0.rawValue < $1.rawValue })
        }
        files.sort { lhs, rhs in
            lhs.changes == rhs.changes ? lhs.path < rhs.path : lhs.changes > rhs.changes
        }
        card.hotFiles = Array(files.prefix(5))
        card.rules = ruleCounts
            .map { RuleCount(ruleId: $0.key, severity: $0.value.0, count: $0.value.1) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.count == rhs.count ? lhs.ruleId < rhs.ruleId : lhs.count > rhs.count
            }
        card.worthALook = findings
            .sorted { lhs, rhs in
                let left = lhs.activeRisk.map(\.severity).max() ?? .info
                let right = rhs.activeRisk.map(\.severity).max() ?? .info
                return left == right ? lhs.ts > rhs.ts : left > right
            }
        card.worthALook = Array(card.worthALook.prefix(findingLimit))
        return card
    }

    private static func absolute(_ path: String, cwd: String?) -> String {
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), let cwd else { return path }
        return (cwd as NSString).appendingPathComponent(path)
    }

    /// A summary safe to paste anywhere: counts, agent names and rule titles —
    /// no command, no path, no project name.
    public func shareableSummary(localizer: Localizer) -> String {
        var lines: [String] = []
        lines.append(localizer.format(.reportShareTitle, Int(until.timeIntervalSince(since) / 86400 + 0.5)))
        lines.append("- " + localizer.format(.reportWork, toolCalls, sessions, projects))
        if !agents.isEmpty {
            lines
                .append("- " + agents.map { "\($0.agent.displayName) \($0.toolCalls)" }
                    .joined(separator: " · "))
        }
        lines.append("- " + localizer.format(.reportShareFiles, filesChanged))
        if rules.isEmpty {
            lines.append("- " + localizer.text(.reportNoFindings))
        } else {
            let named = rules.prefix(4).map { count in
                let title = RuleLocalization.text(forRule: count.ruleId, language: localizer.language)?.title
                    ?? count.ruleId
                return "\(title) ×\(count.count)"
            }
            lines.append("- " + localizer.format(.reportShareFindings, critical, warnings) + ": "
                + named.joined(separator: ", "))
        }
        lines.append("")
        lines.append(localizer.text(.reportShareFooter))
        return lines.joined(separator: "\n")
    }
}
