// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Dispatch
import Foundation
import TrailwardenCore

/// `trailwarden watch` — a live tail of risky commands, as the agents run them.
struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch the agents live and print each finding the moment it is written.",
        discussion: """
        Reads only: transcripts are re-read when the agent appends to them, and
        nothing is sent anywhere. Stop with Ctrl-C.
        """)

    @OptionGroup var store: StoreOptions

    @Option(name: .long, help: "Lowest severity to print: info, warn or critical.")
    var severity: Severity = .warn

    @Flag(name: .long, help: "Print one JSON object per finding instead of text.")
    var json = false

    func run() throws {
        let url = try store.url
        let threshold = severity
        let asJSON = json
        let session = WatchSession(databaseURL: url, threshold: threshold, json: asJSON)
        try session.start()

        if !asJSON {
            Output
                .error(
                    "watching Claude Code, Codex, Gemini CLI, Hermes, opencode, Cursor and Copilot — Ctrl-C to stop")
        }
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler {
            session.stop()
            Foundation.exit(0)
        }
        interrupt.resume()
        dispatchMain()
    }
}

/// The watcher, the store and the guard, all used from the watcher's own queue.
private final class WatchSession: @unchecked Sendable {
    private let databaseURL: URL
    private let json: Bool
    private var guardState: LiveGuard
    private var database: EventStore?
    /// Rebuilt when an allowance or a rule changes in the app while this runs.
    private let rules = CurrentRules()
    private var watcher: TranscriptWatcher?
    private let lock = NSLock()

    init(databaseURL: URL, threshold: Severity, json: Bool) {
        self.databaseURL = databaseURL
        self.json = json
        guardState = LiveGuard(threshold: threshold)
    }

    func start() throws {
        let database = try EventStore(url: databaseURL)
        let engine = try rules.engine(for: database)
        self.database = database
        // Bring the index up to date first, so the first live pass only reads
        // what the agents write from now on.
        _ = try TranscriptScanner(store: database, rules: engine)
            .scan(roots: ScanRoot.standard(), databases: ScanRoot.standardDatabases())
        _ = try guardState.newFindings(in: database)

        let watcher = TranscriptWatcher.standard { [weak self] urls in
            self?.pass(urls)
        }
        guard watcher.start() else {
            throw ValidationError("no transcript folder to watch (run `trailwarden doctor`)")
        }
        self.watcher = watcher
    }

    func stop() {
        watcher?.stop()
    }

    private func pass(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        guard let database, let engine = try? rules.engine(for: database) else { return }
        _ = TranscriptScanner(store: database, rules: engine)
            .scan(changed: urls, roots: ScanRoot.standard(), databases: ScanRoot.standardDatabases())
        guard let fresh = try? guardState.newFindings(in: database) else { return }
        for event in fresh {
            Output.write(json ? Self.json(event) : Self.text(event))
        }
    }

    private static func text(_ event: Event) -> String {
        let alert = LiveAlert(event: event, localizer: Localizer(language: .english))
        let severity = event.activeRisk.map(\.severity).max()?.rawValue.uppercased() ?? "-"
        let ids = event.activeRisk.map(\.ruleId).joined(separator: ",")
        return "\(WhoCommand.stamp(event.ts))  \(severity) \(ids)  \(alert.title)\n"
            + "    \(alert.detailLine)"
    }

    private static func json(_ event: Event) -> String {
        var row: [String: Any] = [
            "ts": Output.timestamp(event.ts),
            "event": event.id,
            "agent": event.agent.rawValue,
            "session": event.sessionId,
            "findings": event.activeRisk.map {
                ["rule": $0.ruleId, "severity": $0.severity.rawValue, "message": $0.englishMessage]
            }
        ]
        if let command = event.command {
            row["command"] = command
        }
        if let cwd = event.cwd {
            row["cwd"] = cwd
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: row,
            options: [.sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
