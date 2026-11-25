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
    /// What the agent actually did today, newest first. The panel leads with
    /// these because "hermes · ~ · 6 events" tells a reader nothing.
    var recentActions: [ActivityItem] = []
    var latestCritical: ActivityItem?
    var messagesToday = 0
    /// Critical findings nobody has reviewed yet.
    var unreviewedCritical = 0
}

/// One transcript directory shown during onboarding.
struct TranscriptRoot: Identifiable, Sendable {
    let agent: Agent
    let path: String
    let files: Int
    let exists: Bool

    var id: String {
        path
    }
}

/// The app's single state holder. The store and the scanner are not `Sendable`,
/// so a scan runs in a detached task that opens its own connection and returns
/// plain numbers; everything else stays on the main actor.
@MainActor
final class AppModel: ObservableObject {
    static let onboardingKey = "trailwarden.onboarding.complete"

    @Published private(set) var snapshot = Snapshot()
    /// Set by the menu bar when a session row is clicked; the main window picks
    /// it up, switches the timeline to that session, and clears it again.
    @Published var sessionToOpen: String?
    /// Bumped when the reader asks to see today's criticals; the window watches
    /// it and switches to the timeline with the finding filter on.
    @Published var findingsRequested = 0
    /// Bumped to show the inbox; the window watches it like `findingsRequested`.
    @Published var inboxRequested = 0
    @Published private(set) var isScanning = false
    /// Byte-weighted progress of the running scan; nil when none is running.
    @Published private(set) var scanProgress: ScanProgress?
    /// Sessions that wrote something in the last two minutes.
    @Published private(set) var liveSessions: Set<String> = []
    @Published private(set) var lastScanSummary: String?
    @Published var errorMessage: String?
    @Published var onboardingDone: Bool
    /// Set when a notification is clicked: the window opens on that event.
    @Published var eventToSelect: String?
    /// Bumped to ask the menu bar label (always on screen) to open the main window.
    @Published var windowRequested = 0
    /// Bumped whenever the index changed under the views: a new snapshot, a
    /// live pass, an answered notification. The open inbox reloads on it.
    @Published private(set) var indexVersion = 0
    private var isRefreshing = false
    private var refreshPending = false

    /// The live guard. Lazy so its callback can refer back to the model.
    lazy var live = LiveMonitor(databaseURL: databaseURL) { [weak self] in
        self?.indexChanged()
    }

    // Rules screen state: the effective rule list, the active allowances, and the
    // outcome of the last re-run.
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var allowances: [Allowance] = []
    @Published private(set) var ruleStatus: String?
    @Published private(set) var isReapplying = false

    let databaseURL: URL

    init(databaseURL: URL? = nil) {
        // TRAILWARDEN_DB lets the app be opened against another index — the demo
        // database, or a copy taken for a screenshot — without touching the real one.
        let override = EventStore.environmentOverride
        self.databaseURL = databaseURL
            ?? override
            ?? (try? EventStore.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trailwarden.sqlite")
        onboardingDone = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        loadRules()
        refresh()
        NotificationCenter.default.addObserver(
            forName: .trailwardenOpenEvent,
            object: nil,
            queue: .main)
        { [weak self] note in
            let session = note.userInfo?["session"] as? String
            let event = note.userInfo?["event"] as? String
            MainActor.assumeIsolated {
                self?.openEvent(event, in: session)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .trailwardenOpenInbox,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.openInbox()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .trailwardenFindingAnswered,
            object: nil,
            queue: .main)
        { [weak self] note in
            let action = note.userInfo?["action"] as? String
            let keys = note.userInfo?["keys"] as? [String] ?? []
            let cwd = note.userInfo?["cwd"] as? String
            MainActor.assumeIsolated {
                guard !keys.isEmpty, let action else { return }
                Task { await self?.answerFindings(keys: keys, action: action, cwd: cwd) }
            }
        }
        // A Dock click or ⌘-Tab on a windowless app asks for the dashboard; the
        // menu bar label owns `openWindow`, so it reacts to this counter.
        NotificationCenter.default.addObserver(
            forName: .trailwardenShowDashboard,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowRequested += 1
            }
        }
        // An index opened with TRAILWARDEN_DB is someone else's — the demo, or a
        // copy for a bug report — so live transcripts are not written into it
        // unless TRAILWARDEN_LIVE=1 asks for that.
        let overridden = ProcessInfo.processInfo.environment["TRAILWARDEN_DB"] != nil
        let liveAllowed = !overridden || ProcessInfo.processInfo.environment["TRAILWARDEN_LIVE"] == "1"
        if onboardingDone, liveAllowed {
            live.sync()
        }
        // The live guard re-grades the history after an update that changed the
        // built-in rules; without it running, the app does it here.
        if onboardingDone, !(liveAllowed && LiveMonitor.isEnabled) {
            Task { await reapplyIfCatalogueChanged() }
        }
    }

    /// Jumps to one event: the window opens on its session with it selected.
    func openEvent(_ eventID: String?, in sessionID: String?) {
        guard let sessionID else { return }
        eventToSelect = eventID
        sessionToOpen = sessionID
        windowRequested += 1
    }

    /// Opens the window on the inbox.
    func openInbox() {
        inboxRequested += 1
        windowRequested += 1
    }

    /// A notification button: "Reviewed", or "Expected in this project", which
    /// allows each rule in that project forever and marks a finding only once
    /// its allowance is stored (the same order the inbox uses). The button
    /// answers every active finding of the event, not just the worst one.
    func answerFindings(keys: [String], action: String, cwd: String?) async {
        var answered: [(key: String, state: ReviewState)] = []
        for key in keys {
            guard action == LiveMonitor.expectedAction else {
                answered.append((key, .reviewed))
                continue
            }
            guard let cwd, let ruleId = FindingKey.ruleID(of: key) else { continue }
            let stored = await allow(Allowance(ruleId: ruleId, scope: .projectRule(project: cwd), until: nil))
            if stored {
                answered.append((key, .expected))
            }
        }
        do {
            let store = try EventStore(url: databaseURL)
            for answer in answered {
                try store.setReview(answer.state, for: answer.key)
            }
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
        indexChanged()
    }

    // MARK: - Reading

    /// Reloads the snapshot off the main actor and publishes it. Requests that
    /// arrive while a load runs are folded into one more load after it, so a
    /// burst of live passes costs at most two reads of the index.
    func refresh() {
        refreshPending = true
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { await drainRefreshes() }
    }

    /// Something wrote to the index (a live pass, an answered notification):
    /// views that keep their own copy, like an open inbox, reload too.
    func indexChanged() {
        indexVersion += 1
        refresh()
    }

    private func drainRefreshes() async {
        defer { isRefreshing = false }
        while refreshPending {
            refreshPending = false
            let url = databaseURL
            let loaded = await Task.detached(priority: .utility) {
                Result { try Snapshot.load(at: url) }
            }.value
            switch loaded {
            case let .success(result):
                if result.snapshot != snapshot {
                    snapshot = result.snapshot
                    indexVersion += 1
                }
                liveSessions = result.liveSessions
                errorMessage = nil
            case let .failure(error):
                errorMessage = TechnicalDetails.errorText(error)
            }
        }
    }

    // MARK: - Scanning

    /// "Scanning… 42%" once the scan knows its size, "Scanning…" before that.
    var scanLabel: String {
        guard let scanProgress, scanProgress.filesTotal > 0 else { return L(.scanning) }
        return Lf(.scanningProgress, [Int(scanProgress.fraction * 100)])
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            scanProgress = nil
        }

        let url = databaseURL
        // Built here, on the main actor, so the detached scan never captures `self`.
        let publish: @MainActor @Sendable (ScanProgress) -> Void = { [weak self] progress in
            self?.scanProgress = progress
        }
        let outcome = await Task.detached(priority: .userInitiated) { () -> (
            events: Int,
            failure: String?) in
            do {
                let store = try EventStore(url: url)
                let engine = try RuleEngine.grading(store, rules: RulePreferences.effectiveRules())
                // The first scan of a long history takes minutes; show it moving,
                // but only when the whole percent changes.
                var shown = -1
                let report = try TranscriptScanner(
                    store: store,
                    rules: engine,
                    archive: TranscriptArchive.ifEnabled(databaseURL: url, store: store))
                    .scan(roots: ScanRoot.standard(), databases: ScanRoot.standardDatabases()) { progress in
                        let percent = Int(progress.fraction * 100)
                        guard percent != shown else { return }
                        shown = percent
                        Task { @MainActor in publish(progress) }
                    }
                // Settings files are checked once per full scan, never on the live path.
                // A store error here is shown like a scan failure but does not fail the scan.
                var settingsFailure: String?
                do {
                    try AgentSettingsScan.refresh(store: store)
                } catch {
                    settingsFailure = TechnicalDetails.errorText(error)
                }
                let failure = report.failures.first.map { TechnicalDetails.errorText(raw: $0) }
                    ?? settingsFailure
                return (report.eventsStored, failure)
            } catch {
                return (0, TechnicalDetails.errorText(error))
            }
        }.value

        if let failure = outcome.failure {
            errorMessage = failure
        }
        lastScanSummary = LocalizationStore.current.format(.eventCount, outcome.events)
        indexChanged()
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
            allowances = try EventStore(url: databaseURL).allowances()
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }

    /// Turns a rule off or on, or re-grades it. The edit is saved, then the whole
    /// index is re-run so the timeline reflects it immediately.
    func updateRule(_ ruleId: String, enabled: Bool? = nil, severity: Severity? = nil) async {
        guard let index = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        rulesDirty = true
        let current = rules[index]
        rules[index] = current.with(
            enabled: enabled ?? current.isEnabled,
            severity: severity ?? current.severity)
        await saveAndReapply()
    }

    /// Saves an allowance (a rule's hits in one scope are expected) and re-runs
    /// the rules so the timeline reflects it.
    /// Returns whether the allowance was stored.
    @discardableResult
    func allow(_ allowance: Allowance) async -> Bool {
        rulesDirty = true
        do {
            let store = try EventStore(url: databaseURL)
            try store.addAllowance(allowance)
            allowances = try store.allowances()
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
            return false
        }
        await reapplyRules()
        return true
    }

    func removeAllowance(_ allowance: Allowance) async {
        rulesDirty = true
        do {
            let store = try EventStore(url: databaseURL)
            try store.removeAllowance(id: allowance.id)
            allowances = try store.allowances()
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
            return
        }
        await reapplyRules()
    }

    private func saveAndReapply() async {
        do {
            if let url = preferencesURL {
                try RulePreferences.save(RulePreferences.preferences(from: rules), to: url)
            }
            // The live guard rebuilds its rule engine when this moves.
            try EventStore(url: databaseURL).bumpRulesGeneration()
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
            return
        }
        await reapplyRules()
    }

    /// Re-runs the rules over the whole index once after an update changed the
    /// built-in catalogue, with the reader's preferences and allowances.
    func reapplyIfCatalogueChanged() async {
        let rulesCopy = rules
        let url = databaseURL
        let changed = await Task.detached(priority: .utility) { () -> Bool in
            do {
                let store = try EventStore(url: url)
                let engine = try RuleEngine.grading(store, rules: rulesCopy)
                return try store.reapplyRulesIfCatalogueChanged(engine: engine)
            } catch {
                NSLog("Trailwarden could not re-apply the rules: %@", String(describing: error))
                return false
            }
        }.value
        if changed {
            refresh()
        }
    }

    /// Re-runs the rules over the stored index. Runs off the main actor because
    /// the store is not `Sendable`; only the summary text comes back. A call
    /// while one runs is not dropped: it asks for one more run after it, and the
    /// allowances are read from the store inside each run.
    func reapplyRules() async {
        reapplyPending = true
        guard !isReapplying else { return }
        isReapplying = true
        defer { isReapplying = false }

        while reapplyPending {
            reapplyPending = false
            rulesDirty = false
            let rulesCopy = rules
            let url = databaseURL
            let summary = await Task.detached(priority: .userInitiated) { () -> (String, [String: Int]) in
                do {
                    let store = try EventStore(url: url)
                    let report = try store.reapplyCurrentRules { rulesCopy }
                    let counts = try store.ruleHitCounts(matching: EventQuery(onlyFindings: true))
                    let text = LocalizationStore.current.format(
                        .statusScan, report.events, report.changed, report.duration)
                    return (text, counts)
                } catch {
                    return (LocalizationStore.current.format(.statusError, "\(error)"), [:])
                }
            }.value
            ruleStatus = summary.0
            ruleHitCounts = summary.1
        }
        indexChanged()
    }

    private var reapplyPending = false

    /// Set when a rule or an allowance changed and the stored events have not been
    /// re-run yet (true at launch, so the first visit fills the hit counts);
    /// the Rules tab reapplies on appear only then.
    private(set) var rulesDirty = true
    @Published private(set) var ruleHitCounts: [String: Int] = [:]
    @Published private(set) var maintenanceStatus: String?
    @Published private(set) var usage: [Agent: TokenTotals] = [:]
    @Published private(set) var dailyUsage: [DailyTokens] = []
    @Published private(set) var modelUsage: [ModelUsage] = []
    @Published private(set) var costEstimate = CostEstimate()
    @Published private(set) var prices = PriceTable.builtIn
    @Published private(set) var priceFileError: String?
    @Published private(set) var usageUpdatedAt: Date?
    /// The period the usage screen last asked for, so a price change can redo
    /// the same estimate.
    private var usageDays = 30

    /// One price book for Settings and the price window, so both show the same
    /// state and a change in one is seen in the other.
    lazy var priceBook: PriceBook = {
        let book = PriceBook(databaseURL: databaseURL)
        book.onChange = { [weak self] in
            guard let self else { return }
            Task { await self.loadUsage(days: self.usageDays) }
        }
        return book
    }()

    private struct LoadedUsage {
        var byAgent: [Agent: TokenTotals] = [:]
        var daily: [DailyTokens] = []
        var byModel: [ModelUsage] = []
        var prices = PriceTable.builtIn
        var priceFileError: String?
    }

    /// Tokens come from the transcripts; the dollars are an estimate at the
    /// API prices in use (built in, downloaded, or the reader's own), never a bill.
    func loadUsage(days: Int = 30) async {
        usageDays = days
        let database = databaseURL
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        let loaded = await Task.detached(priority: .utility) { () -> LoadedUsage in
            var result = LoadedUsage()
            let prices = PriceTable.load()
            result.prices = prices.table
            result.priceFileError = prices.problem
            do {
                let store = try EventStore(url: database)
                result.byAgent = try store.tokenTotalsByAgent(since: since)
                result.daily = try store.dailyTokens(since: since)
                result.byModel = try store.tokenCountsByModel(since: since)
            } catch {
                NSLog("loadUsage failed: %@", String(describing: error))
            }
            return result
        }.value
        usage = loaded.byAgent
        dailyUsage = loaded.daily
        modelUsage = loaded.byModel
        prices = loaded.prices
        priceFileError = loaded.priceFileError
        costEstimate = loaded.prices.estimate(loaded.byModel)
        usageUpdatedAt = Date()
    }

    /// Deletes events older than the retention window; file signatures are kept,
    /// so a later scan does not bring them back.
    func prune(retention: RetentionChoice) async {
        guard let retentionDays = retention.days else { return }
        let url = databaseURL
        let message = await Task.detached(priority: .utility) { () -> String in
            do {
                let store = try EventStore(url: url)
                let report = try store.prune(eventsOlderThanDays: retentionDays)
                return LocalizationStore.current.format(
                    .statusPrune, report.removedEvents, report.removedSessions)
            } catch {
                return LocalizationStore.current.format(.statusPruneFailed, "\(error)")
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
                var query = EventQuery(since: Date().addingTimeInterval(-Double(days) * 86400))
                query.includeRawJSON = false
                let events = try store.events(matching: query)
                let sessions = try store.sessions(agents: nil)
                let selection = AuditSelection(
                    since: query.since,
                    until: Date(),
                    agents: [],
                    minimumSeverity: nil,
                    generatedAt: Date())
                let outcome = try ExportWriter.write(
                    format: format,
                    sessions: sessions,
                    events: events,
                    selection: selection,
                    to: url)
                return LocalizationStore.current.format(
                    .statusExport,
                    url.lastPathComponent, outcome.events, outcome.findings, outcome.duration)
            } catch {
                return LocalizationStore.current.format(.statusExportFailed, "\(error)")
            }
        }.value
        maintenanceStatus = message
    }

    // MARK: - Onboarding

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        onboardingDone = true
        live.sync()
    }
}

extension Notification.Name {
    /// Posted by the notification delegate with `session` and `event` in userInfo.
    static let trailwardenOpenEvent = Notification.Name("app.trailwarden.openEvent")
    static let trailwardenOpenInbox = Notification.Name("app.trailwarden.openInbox")
    static let trailwardenFindingAnswered = Notification.Name("app.trailwarden.findingAnswered")
    /// Posted when the Dock tile or ⌘-Tab asks for the window: the app is open,
    /// but nothing of it is on screen.
    static let trailwardenShowDashboard = Notification.Name("app.trailwarden.showDashboard")
}
