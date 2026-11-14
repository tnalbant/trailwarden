// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Write a redacted audit record. Markdown lists sessions and findings; "
            + "JSON carries every event in the window."
    )

    @OptionGroup var store: StoreOptions

    @Flag(name: .long, help: "Write the JSON report (schema 1).")
    var json = false

    @Flag(name: .long, help: "Write the Markdown report.")
    var md = false

    @Option(name: .long, help: "Output file; standard output when omitted.")
    var out: String?

    @Option(name: .long, help: "How far back: 30d, 12h, an ISO date, or all.")
    var since = "30d"

    @Option(name: .long, help: "Agent to include: all, claude or codex.")
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
        _ = try TranscriptScanner(store: database, rules: engine).scan(roots: ScanRoot.standard(agents: agents))

        let events = try database.events(
            matching: EventQuery(since: sinceDate, agents: agents, minimumSeverity: severity)
        )
        let sessions = try database.sessions(agents: agents)
        let until = Date()
        let selection = AuditSelection(
            since: sinceDate,
            until: until,
            agents: agent.list,
            minimumSeverity: severity,
            generatedAt: until
        )

        let redactor = Redactor(level: redact)
        let body: String
        if json {
            body = String(
                decoding: try JSONReport.data(
                    sessions: sessions,
                    events: events,
                    selection: selection,
                    redactor: redactor
                ),
                as: UTF8.self
            )
        } else {
            body = MarkdownReport.render(
                sessions: sessions,
                events: events.map { redactor.redactForExport($0) },
                selection: selection
            )
        }

        if let out {
            let url = URL(fileURLWithPath: out)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let summary = AuditReport.summarize(sessions: sessions, events: events)
            Output.write(
                "wrote \(url.path) — \(summary.events) events, \(summary.findings) findings "
                    + "(\(summary.critical) critical)"
            )
        } else {
            Output.write(body)
        }

        if AuditReport.summarize(sessions: sessions, events: events).critical > 0 {
            throw ExitCode(1)
        }
    }
}
