// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan agent transcripts, apply the rules and report findings. "
            + "Text and Markdown list findings; JSON carries every event in the window."
    )

    @OptionGroup var store: StoreOptions

    @Option(name: .long, help: "How far back to report: 7d, 12h, 90m, an ISO date, or all.")
    var since = "all"

    @Option(name: .long, help: "Agent to scan: all, claude or codex.")
    var agent: AgentOption = .all

    @Option(name: .long, help: "Minimum severity to report: info, warn or critical.")
    var severity: Severity?

    @Flag(name: .long, help: "Print the JSON report.")
    var json = false

    @Flag(name: .long, help: "Print a Markdown report.")
    var md = false

    func run() throws {
        if json && md {
            throw ValidationError("choose one of --json or --md")
        }
        let sinceDate = try TimeWindow.parse(since)
        let agents = agent.agents
        let database = try store.open()
        let engine = try RuleEngine.builtIn(mutes: database.mutes())
        let scanner = TranscriptScanner(store: database, rules: engine)

        let report = try scanner.scan(
            roots: ScanRoot.standard(agents: agents),
            databases: ScanRoot.standardDatabases(agents: agents)
        )
        let query = EventQuery(
            since: sinceDate,
            agents: agents,
            minimumSeverity: severity,
            onlyFindings: !json && !md
        )
        let events = try database.events(matching: query)
        let sessions = try database.sessions(agents: agents)
        let until = Date()
        let selection = AuditSelection(
            since: sinceDate,
            until: until,
            agents: agent.list,
            minimumSeverity: severity,
            generatedAt: until
        )

        if json {
            let data = try JSONReport.data(sessions: sessions, events: events, selection: selection)
            Output.write(String(decoding: data, as: UTF8.self))
        } else if md {
            Output.write(MarkdownReport.render(sessions: sessions, events: events, selection: selection))
        } else {
            Output.write(textReport(report: report, events: events, since: sinceDate))
        }

        let summary = AuditReport.summarize(sessions: sessions, events: events)
        if summary.critical > 0 {
            throw ExitCode(1)
        }
    }

    private func textReport(report: ScanReport, events: [Event], since: Date?) -> String {
        var lines: [String] = []
        lines.append(
            "scanned \(report.filesSeen) files: \(report.filesParsed) parsed, "
                + "\(report.filesUnchanged) unchanged, \(report.eventsStored) events, "
                + "\(report.skippedLines) skipped lines"
        )
        for failure in report.failures {
            lines.append("  failed: \(failure)")
        }
        let window = since.map { "since \(Output.timestamp($0))" } ?? "all time"
        let summary = AuditReport.summarize(sessions: [], events: events)
        lines.append(
            "findings (\(window)): \(summary.findings)  critical \(summary.critical)  warn \(summary.warn)"
        )
        for event in events.prefix(30) {
            let hits = event.risk
                .sorted { $0.severity > $1.severity }
                .map { "\($0.severity.rawValue) \($0.ruleId)" }
                .joined(separator: ", ")
            let detail = event.command ?? event.preview ?? "-"
            lines.append(
                "  \(Output.timestamp(event.ts))  \(hits)  \(event.agent.rawValue)  "
                    + "\(event.tool ?? "-")  \(detail.prefix(100))"
            )
        }
        if events.count > 30 {
            lines.append("  … \(events.count - 30) more; use --md or --json for the full list")
        }
        return lines.joined(separator: "\n")
    }
}
