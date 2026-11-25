// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan agent transcripts, apply the rules and report findings. "
            + "Text and Markdown list findings; JSON carries every event in the window.")

    @OptionGroup var store: StoreOptions

    @Option(name: .long, help: "How far back to report: 7d, 12h, 90m, an ISO date, or all.")
    var since = "all"

    @Option(
        name: .long,
        help: "Agent to scan: all, claude, codex, gemini, hermes, opencode, cursor or copilot.")
    var agent: AgentOption = .all

    @Option(name: .long, help: "Minimum severity to report: info, warn or critical.")
    var severity: Severity?

    @Flag(name: .long, help: "Print the JSON report.")
    var json = false

    @Flag(name: .long, help: "Print a Markdown report.")
    var md = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Exit with status 1 when a finding of this severity or worse is in the window: "
                + "critical (default), warn, info or none."))
    var failOn: FailThreshold = .critical

    @Flag(
        name: .long,
        help: "Also list findings marked reviewed, expected or false alarm, and hits an allowance covers.")
    var includeReviewed = false

    func run() throws {
        if json, md {
            throw ValidationError("choose one of --json or --md")
        }
        let sinceDate = try TimeWindow.parse(since)
        let agents = agent.agents
        let database = try store.open()
        let engine = try RuleEngine.grading(database, rules: RuleCatalog.builtIn())
        // After an update that changed the built-in rules, the history is
        // re-graded once, with the reader's preferences, before the scan.
        try database.reapplyRulesIfCatalogueChanged(
            engine: RuleEngine.grading(database, rules: RulePreferences.effectiveRules()))
        let scanner = TranscriptScanner(store: database, rules: engine)

        // A progress line on a terminal only: scripts and CI read stdout and a
        // redirected stderr, and neither should fill with carriage returns.
        let showProgress = isatty(STDERR_FILENO) == 1
        var shown = -1
        let report = try scanner.scan(
            roots: ScanRoot.standard(agents: agents),
            databases: ScanRoot.standardDatabases(agents: agents))
        { progress in
            guard showProgress else { return }
            let percent = Int(progress.fraction * 100)
            guard percent != shown else { return }
            shown = percent
            Output.error(
                "\rscanning \(percent)%  (\(progress.filesDone)/\(progress.filesTotal) files)",
                newline: false)
        }
        if showProgress, shown >= 0 {
            Output.error("\r\u{1B}[K", newline: false)
        }
        let query = EventQuery(
            since: sinceDate,
            agents: agents,
            minimumSeverity: severity,
            onlyFindings: !json && !md)
        let found = try database.events(matching: query)
        let allowedTotal = ScanVisibility.allowedTotal(of: found)
        var events = try visible(found, in: database)
        if !json, !md {
            events.removeAll { $0.risk.isEmpty }
        }
        let sessions = try database.sessions(agents: agents)
        let until = Date()
        let selection = AuditSelection(
            since: sinceDate,
            until: until,
            agents: agent.list,
            minimumSeverity: severity,
            generatedAt: until)

        if json {
            let extras = try JSONReport.Extras(
                reviews: database.reviewStates(for: ScanVisibility.reviewKeys(of: events)),
                allowedTotal: allowedTotal)
            let data = try JSONReport.data(
                sessions: sessions, events: events, selection: selection, extras: extras)
            Output.write(String(decoding: data, as: UTF8.self))
        } else if md {
            Output.write(MarkdownReport.render(sessions: sessions, events: events, selection: selection))
        } else {
            Output.write(textReport(report: report, events: events, allowed: allowedTotal, since: sinceDate))
        }

        // CI gate: same window, agents and visibility as the report, but its own
        // severity, so `--severity critical --fail-on warn` still fails on a warning.
        // It counts only what the report prints.
        if let threshold = failOn.severity {
            let gate = try visible(
                database.events(matching: EventQuery(
                    since: sinceDate, agents: agents, minimumSeverity: threshold, onlyFindings: true,
                    includeRawJSON: false)),
                in: database)
            if ScanVisibility.gateFails(visibleEvents: gate, threshold: threshold) {
                throw ExitCode(1)
            }
        }
    }

    private func visible(_ events: [Event], in database: EventStore) throws -> [Event] {
        let states = includeReviewed
            ? [:] : try database.reviewStates(for: ScanVisibility.reviewKeys(of: events))
        return ScanVisibility.visible(events, states: states, includeReviewed: includeReviewed)
    }

    private func textReport(report: ScanReport, events: [Event], allowed: Int, since: Date?) -> String {
        var lines: [String] = []
        lines.append(
            "scanned \(report.filesSeen) files: \(report.filesParsed) parsed, "
                + "\(report.filesUnchanged) unchanged, \(report.eventsStored) events, "
                + "\(report.skippedLines) skipped lines")
        for failure in report.failures {
            lines.append("  failed: \(failure)")
        }
        let window = since.map { "since \(Output.timestamp($0))" } ?? "all time"
        let summary = AuditReport.summarize(sessions: [], events: events)
        lines.append(
            "findings (\(window)): \(summary.findings)  critical \(summary.critical)  warn \(summary.warn)")
        lines.append("allowed (covered by an allowance): \(allowed)")
        for event in events.prefix(30) {
            let hits = event.risk
                .sorted { $0.severity > $1.severity }
                .map { "\($0.severity.rawValue) \($0.ruleId)\($0.allowed ? " (allowed)" : "")" }
                .joined(separator: ", ")
            let detail = event.command ?? event.preview ?? "-"
            lines.append(
                "  \(Output.timestamp(event.ts))  \(hits)  \(event.agent.rawValue)  "
                    + "\(event.tool ?? "-")  \(detail.prefix(100))")
        }
        if events.count > 30 {
            lines.append("  … \(events.count - 30) more; use --md or --json for the full list")
        }
        return lines.joined(separator: "\n")
    }
}

/// `--fail-on`: the lowest severity that makes `scan` exit with 1.
enum FailThreshold: String, ExpressibleByArgument, CaseIterable {
    case critical
    case warn
    case info
    case none

    var severity: Severity? {
        switch self {
        case .critical: .critical
        case .warn: .warn
        case .info: .info
        case .none: nil
        }
    }
}
