// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// Everything the menu bar shows, gathered off the store in one pass.
struct Snapshot: Sendable, Equatable {
    var criticalToday = 0
    var warnToday = 0
    var sessions: [SessionSummary] = []
    var totalEvents = 0

    var recentSessions: [SessionSummary] {
        Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }
}

/// One transcript directory shown during onboarding.
struct TranscriptRoot: Identifiable, Sendable {
    let agent: Agent
    let path: String
    let files: Int
    let exists: Bool

    var id: String { path }
}

/// The app's single state holder. The store and the scanner are not `Sendable`,
/// so a scan runs in a detached task that opens its own connection and returns
/// plain numbers; everything else stays on the main actor.
@MainActor
final class AppModel: ObservableObject {
    static let onboardingKey = "trailwarden.onboarding.complete"

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanSummary: String?
    @Published var errorMessage: String?
    @Published var onboardingDone: Bool

    // Rules screen state: the effective rule list, the active mutes, and the
    // outcome of the last re-run.
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var mutes: [Mute] = []
    @Published private(set) var ruleStatus: String?
    @Published private(set) var isReapplying = false

    let databaseURL: URL

    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
            ?? (try? EventStore.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trailwarden.sqlite")
        self.onboardingDone = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        loadRules()
        refresh()
    }

    // MARK: - Reading

    func refresh() {
        do {
            snapshot = try Self.loadSnapshot(at: databaseURL)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private static func loadSnapshot(at url: URL) throws -> Snapshot {
        let store = try EventStore(url: url)
        var snapshot = Snapshot()
        snapshot.sessions = try store.sessions()
        snapshot.totalEvents = try store.eventCount()

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let today = try store.events(matching: EventQuery(since: startOfDay, onlyFindings: true))
        for event in today {
            switch event.risk.map(\.severity).max() {
            case .critical: snapshot.criticalToday += 1
            case .warn: snapshot.warnToday += 1
            default: break
            }
        }
        return snapshot
    }

    // MARK: - Scanning

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let url = databaseURL
        let outcome = await Task.detached(priority: .userInitiated) { () -> (events: Int, failure: String?) in
            do {
                let store = try EventStore(url: url)
                let engine = try RuleEngine.builtIn(mutes: store.mutes())
                let report = try TranscriptScanner(store: store, rules: engine)
                    .scan(roots: ScanRoot.standard())
                return (report.eventsStored, report.failures.first)
            } catch {
                return (0, String(describing: error))
            }
        }.value

        if let failure = outcome.failure {
            errorMessage = failure
        }
        lastScanSummary = "\(outcome.events) events indexed"
        refresh()
    }

    // MARK: - Rules

    private var preferencesURL: URL? {
        try? RulePreferences.defaultURL()
    }

    func loadRules() {
        do {
            let builtIn = try RuleCatalog.builtIn()
            let stored = try preferencesURL.map { try RulePreferences.load(from: $0) } ?? []
            rules = RulePreferences.apply(stored, to: builtIn)
            mutes = try EventStore(url: databaseURL).mutes()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Turns a rule off or on, or re-grades it. The edit is saved, then the whole
    /// index is re-run so the timeline reflects it immediately.
    func updateRule(_ ruleId: String, enabled: Bool? = nil, severity: Severity? = nil) async {
        guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        let current = rules[index]
        rules[index] = current.with(
            enabled: enabled ?? current.isEnabled,
            severity: severity ?? current.severity
        )
        await saveAndReapply()
    }

    /// Silences one rule for one situation (the normalized command, or the first
    /// path when there is no command) for 30 days.
    func mute(ruleId: String, target: String, days: Int = 30) async {
        let mute = Mute(
            ruleId: ruleId,
            target: target,
            until: Date().addingTimeInterval(Double(days) * 86_400)
        )
        do {
            let store = try EventStore(url: databaseURL)
            try store.addMute(mute)
            mutes = try store.mutes()
        } catch {
            errorMessage = String(describing: error)
            return
        }
        await reapplyRules()
    }

    func removeMute(_ mute: Mute) async {
        do {
            let store = try EventStore(url: databaseURL)
            try store.removeMute(mute)
            mutes = try store.mutes()
        } catch {
            errorMessage = String(describing: error)
            return
        }
        await reapplyRules()
    }

    private func saveAndReapply() async {
        do {
            if let url = preferencesURL {
                try RulePreferences.save(RulePreferences.preferences(from: rules), to: url)
            }
        } catch {
            errorMessage = String(describing: error)
            return
        }
        await reapplyRules()
    }

    /// Re-runs the rules over the stored index. Runs off the main actor because
    /// the store is not `Sendable`; only the summary text comes back.
    func reapplyRules() async {
        guard !isReapplying else { return }
        isReapplying = true
        defer { isReapplying = false }

        let rulesCopy = rules
        let mutesCopy = mutes
        let url = databaseURL
        let summary = await Task.detached(priority: .userInitiated) { () -> (String, [String: Int]) in
            do {
                let store = try EventStore(url: url)
                let engine = try RuleEngine(rules: rulesCopy, mutes: mutesCopy)
                let report = try engine.reapply(to: store)
                let counts = try store.ruleHitCounts(matching: EventQuery(onlyFindings: true))
                let text = String(
                    format: "%d olay tarandı · %d olay güncellendi · %.2f sn",
                    report.events, report.changed, report.duration
                )
                return (text, counts)
            } catch {
                return ("Hata: \(error)", [:])
            }
        }.value

        ruleStatus = summary.0
        ruleHitCounts = summary.1
        refresh()
    }

    @Published private(set) var ruleHitCounts: [String: Int] = [:]
    @Published private(set) var maintenanceStatus: String?
    @Published private(set) var usage: [Agent: TokenTotals] = [:]
    @Published private(set) var dailyUsage: [DailyTokens] = []
    @Published private(set) var usageUpdatedAt: Date?

    /// Tokens come from the transcript; a price would not, so none is printed.
    func loadUsage(days: Int = 30) async {
        let database = databaseURL
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        let loaded = await Task.detached(priority: .utility) { () -> ([Agent: TokenTotals], [DailyTokens]) in
            do {
                let store = try EventStore(url: database)
                return (
                    try store.tokenTotalsByAgent(since: since),
                    try store.dailyTokens(since: since)
                )
            } catch {
                NSLog("loadUsage failed: %@", String(describing: error))
                return ([:], [])
            }
        }.value
        usage = loaded.0
        dailyUsage = loaded.1
        usageUpdatedAt = Date()
    }

    /// Deletes events older than the retention window; file signatures are kept,
    /// so a later scan does not bring them back.
    func prune(retentionDays: Int) async {
        let url = databaseURL
        let message = await Task.detached(priority: .utility) { () -> String in
            do {
                let store = try EventStore(url: url)
                let report = try store.prune(eventsOlderThanDays: retentionDays)
                return "Silinen: \(report.removedEvents) olay, \(report.removedSessions) oturum"
            } catch {
                return "Temizlik başarısız: \(error)"
            }
        }.value
        maintenanceStatus = message
        refresh()
    }

    /// Writes the same audit record the CLI produces, through the same writer.
    func export(format: AuditFormat, days: Int, to url: URL) async {
        let database = databaseURL
        let message = await Task.detached(priority: .userInitiated) { () -> String in
            do {
                let store = try EventStore(url: database)
                var query = EventQuery(since: Date().addingTimeInterval(-Double(days) * 86_400))
                query.includeRawJSON = false
                let events = try store.events(matching: query)
                let sessions = try store.sessions(agents: nil)
                let selection = AuditSelection(
                    since: query.since,
                    until: Date(),
                    agents: [],
                    minimumSeverity: nil,
                    generatedAt: Date()
                )
                let outcome = try ExportWriter.write(
                    format: format,
                    sessions: sessions,
                    events: events,
                    selection: selection,
                    to: url
                )
                return String(
                    format: "%@ · %d olay, %d bulgu · %.2f sn",
                    url.lastPathComponent, outcome.events, outcome.findings, outcome.duration
                )
            } catch {
                return "Dışa aktarma başarısız: \(error)"
            }
        }.value
        maintenanceStatus = message
    }

    // MARK: - Onboarding

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        onboardingDone = true
    }

    /// What the app will read, with a live count per transcript root.
    static func transcriptRoots() -> [TranscriptRoot] {
        ScanRoot.standard().map { root in
            let exists = FileManager.default.fileExists(atPath: root.directory.path)
            return TranscriptRoot(
                agent: root.agent,
                path: root.directory.path,
                files: exists ? countTranscripts(in: root.directory) : 0,
                exists: exists
            )
        }
    }

    private static func countTranscripts(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            count += 1
        }
        return count
    }
}
