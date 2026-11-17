// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Write a redacted audit record. Markdown lists sessions and findings; "
            + "JSON carries every event in the window.")

    @OptionGroup var store: StoreOptions

    @Flag(name: .long, help: "Write the JSON report (schema 1).")
    var json = false

    @Flag(name: .long, help: "Write the Markdown report.")
    var md = false

    @Option(name: .long, help: "Output file; standard output when omitted.")
    var out: String?

    @Option(name: .long, help: "How far back: 30d, 12h, an ISO date, or all.")
    var since = "30d"

    @Option(
        name: .long,
        help: "Agent to include: all, claude, codex, gemini, hermes, opencode, cursor or copilot.")
    var agent: AgentOption = .all

    @Option(name: .long, help: "Only include events at or above this severity.")
    var severity: Severity?

    @Option(name: .long, help: "Redaction level: normal or strict.")
    var redact: RedactionLevel = .normal

    func run() throws {
        guard json != md else {
            throw ValidationError("choose exactly one of --json or --md")
        }
        let sinceDate = try TimeWindow.parse(since)
        let agents = agent.agents
        let database = try store.open()

        // Make sure the record reflects the transcripts as they are now; the second
        // scan of an unchanged tree costs milliseconds (size + mtime signatures).
        let engine = try RuleEngine.builtIn(mutes: database.mutes())
        _ = try TranscriptScanner(store: database, rules: engine)
            .scan(roots: ScanRoot.standard(agents: agents))

        var query = EventQuery(since: sinceDate, agents: agents, minimumSeverity: severity)
        query.includeRawJSON = false
        let events = try database.events(matching: query)
        let sessions = try database.sessions(agents: agents)
        let until = Date()
        let selection = AuditSelection(
            since: sinceDate,
            until: until,
            agents: agent.list,
            minimumSeverity: severity,
            generatedAt: until)

        // The app writes through the same writer, so the two cannot drift apart.
        let format: AuditFormat = json ? .json : .markdown
        let redactor = Redactor(level: redact)

        if let out {
            let outcome = try ExportWriter.write(
                format: format,
                sessions: sessions,
                events: events,
                selection: selection,
                redactor: redactor,
                to: URL(fileURLWithPath: out))
            Output.write(
                "wrote \(outcome.url.path) — \(outcome.events) events, \(outcome.findings) findings "
                    + "(\(outcome.critical) critical)")
        } else {
            let data = try ExportWriter.data(
                format: format,
                sessions: sessions,
                events: events,
                selection: selection,
                redactor: redactor)
            Output.write(String(decoding: data, as: UTF8.self))
        }

        if AuditReport.summarize(sessions: sessions, events: events).critical > 0 {
            throw ExitCode(1)
        }
    }
}
