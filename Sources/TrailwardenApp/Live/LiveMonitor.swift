// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore
import UserNotifications

/// The live guard: re-reads a transcript as soon as an agent writes to it and
/// raises a notification for a new finding.
///
/// Everything stays on the Mac — FSEvents says which file changed, the file is
/// parsed like any other scan, and the notification is local. The panel and
/// the timeline also stay current without a "Scan" click, because every pass
/// writes to the same index.
@MainActor
final class LiveMonitor: ObservableObject {
    static let enabledKey = "trailwarden.live.enabled"
    static let thresholdKey = "trailwarden.live.threshold"

    @Published private(set) var isRunning = false
    @Published private(set) var lastPass: Date?
    @Published private(set) var notificationsAllowed = true

    private var worker: LiveWorker?
    private let databaseURL: URL
    private let onPass: @MainActor () -> Void

    init(databaseURL: URL, onPass: @escaping @MainActor () -> Void) {
        self.databaseURL = databaseURL
        self.onPass = onPass
        UserDefaults.standard.register(defaults: [Self.enabledKey: true, Self.thresholdKey: "critical"])
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var threshold: Severity {
        Severity(rawValue: UserDefaults.standard.string(forKey: thresholdKey) ?? "") ?? .critical
    }

    /// Starts when the setting is on, stops when it is off; safe to call often.
    func sync() {
        if Self.isEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard worker == nil else { return }
        let worker = LiveWorker(databaseURL: databaseURL, threshold: Self.threshold) { [weak self] in
            Task { @MainActor in
                self?.lastPass = Date()
                self?.onPass()
            }
        }
        self.worker = worker
        isRunning = true
        requestPermission()
        Task.detached(priority: .utility) {
            let started = worker.start()
            await MainActor.run { [weak self] in
                if !started {
                    self?.worker = nil
                    self?.isRunning = false
                }
                self?.lastPass = Date()
                self?.onPass()
            }
        }
    }

    func stop() {
        worker?.stop()
        worker = nil
        isRunning = false
    }

    /// A new threshold applies from the next start.
    func restart() {
        stop()
        sync()
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert,
            .sound,
            .badge
        ]) { granted, _ in
            Task { @MainActor [weak self] in
                self?.notificationsAllowed = granted
            }
        }
    }
}

/// The part that runs off the main actor: one store connection, one rule engine
/// and the guard's memory of what it already reported, all touched from the
/// watcher's serial queue only.
private final class LiveWorker: @unchecked Sendable {
    private let databaseURL: URL
    private let threshold: Severity
    private let didPass: @Sendable () -> Void
    private var watcher: TranscriptWatcher?
    private var guardState: LiveGuard
    private var store: EventStore?
    private var engine: RuleEngine?
    private let lock = NSLock()

    init(databaseURL: URL, threshold: Severity, didPass: @escaping @Sendable () -> Void) {
        self.databaseURL = databaseURL
        self.threshold = threshold
        self.didPass = didPass
        guardState = LiveGuard(threshold: threshold)
    }

    /// Catches the index up with a full scan, then watches. The catch-up pass
    /// never notifies: it is history, not news.
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            let store = try EventStore(url: databaseURL)
            let engine = try RuleEngine(rules: Self.effectiveRules(), mutes: store.mutes())
            _ = try TranscriptScanner(store: store, rules: engine)
                .scan(roots: ScanRoot.standard(), databases: ScanRoot.standardDatabases())
            _ = try guardState.newFindings(in: store)
            self.store = store
            self.engine = engine
        } catch {
            NSLog("Trailwarden live guard could not start: %@", String(describing: error))
            return false
        }
        let watcher = TranscriptWatcher.standard { [weak self] urls in
            self?.pass(urls)
        }
        guard watcher.start() else { return false }
        self.watcher = watcher
        return true
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    /// The rule set the reader configured: built-ins with their switches and
    /// severities from the Rules window.
    private static func effectiveRules() throws -> [Rule] {
        let builtIn = try RuleCatalog.builtIn()
        let stored = try (try? RulePreferences.defaultURL()).map { try RulePreferences.load(from: $0) } ?? []
        return RulePreferences.apply(stored, to: builtIn)
    }

    private func pass(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        guard let store, let engine else { return }
        let report = TranscriptScanner(store: store, rules: engine)
            .scan(changed: urls, roots: ScanRoot.standard(), databases: ScanRoot.standardDatabases())
        let fresh = (try? guardState.newFindings(in: store)) ?? []
        for event in fresh.suffix(3) {
            Self.notify(event)
        }
        if fresh.count > 3 {
            Self.notifySummary(extra: fresh.count - 3)
        }
        if report.eventsStored > 0 || !fresh.isEmpty {
            didPass()
        }
    }

    private static func notify(_ event: Event) {
        let alert = LiveAlert(event: event, localizer: LocalizationStore.current)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.subtitle = alert.subtitle
        content.body = alert.body
        content.sound = event.risk.contains { $0.severity == .critical } ? .default : nil
        content.threadIdentifier = event.sessionId
        content.userInfo = ["event": event.id, "session": event.sessionId]
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func notifySummary(extra: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Trailwarden"
        content.body = LocalizationStore.current.format(.liveMoreFindings, extra)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
