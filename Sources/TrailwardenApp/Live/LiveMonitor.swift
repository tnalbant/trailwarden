// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
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

    /// Notification categories: the answer buttons of a finding. A finding with no
    /// project folder gets no "expected in this project" button.
    nonisolated static let findingCategory = "trailwarden.finding"
    nonisolated static let findingNoProjectCategory = "trailwarden.finding.noproject"
    nonisolated static let reviewedAction = "reviewed"
    nonisolated static let expectedAction = "expected"
    nonisolated static let openAction = "open"

    /// Registers the categories in the language current at launch.
    static func registerCategories() {
        let localizer = LocalizationStore.current
        let reviewed = UNNotificationAction(identifier: reviewedAction, title: localizer.text(.inboxReviewed))
        let expected = UNNotificationAction(
            identifier: expectedAction, title: localizer.text(.inboxExpectedHere))
        let open = UNNotificationAction(
            identifier: openAction, title: localizer.text(.inboxOpen), options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: findingCategory, actions: [reviewed, expected, open],
                intentIdentifiers: [], options: []),
            UNNotificationCategory(
                identifier: findingNoProjectCategory, actions: [reviewed, open],
                intentIdentifiers: [], options: [])
        ])
    }

    /// What the system says about banners. The app can ask, and it can read the
    /// answer back after the reader changes it in System Settings.
    enum NotificationPermission: Sendable {
        case unknown, allowed, denied
    }

    @Published private(set) var isRunning = false
    @Published private(set) var lastPass: Date?
    @Published private(set) var permission: NotificationPermission = .unknown

    var notificationsAllowed: Bool {
        permission == .allowed
    }

    private var worker: LiveWorker?
    private let databaseURL: URL
    private let onPass: @MainActor () -> Void

    init(databaseURL: URL, onPass: @escaping @MainActor () -> Void) {
        self.databaseURL = databaseURL
        self.onPass = onPass
        UserDefaults.standard.register(defaults: [Self.enabledKey: true, Self.thresholdKey: "critical"])
        Self.registerCategories()
        readNotificationSettings()
        // A grant made in System Settings has to show up without a restart.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor in self?.readNotificationSettings() }
        }
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
        requestNotifications()
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

    /// Asks once. When the answer is already on record the system does not show a
    /// prompt again, so the settings are read back instead of leaving the reader
    /// with a switch and no explanation.
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert,
            .sound,
            .badge
        ]) { [weak self] _, _ in
            Task { @MainActor in self?.readNotificationSettings() }
        }
    }

    /// The current answer, without asking for anything.
    func readNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state: NotificationPermission = switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .allowed
            case .denied: .denied
            default: .unknown
            }
            Task { @MainActor in self?.permission = state }
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
            let engine = try RuleEngine(
                rules: RulePreferences.effectiveRules(),
                allowances: store.allowances())
            // After an update that changed the built-in rules, the history is
            // re-graded once, before the catch-up scan.
            try store.reapplyRulesIfCatalogueChanged(engine: engine)
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
        content.sound = event.activeRisk.contains { $0.severity == .critical } ? .default : nil
        content.threadIdentifier = event.sessionId
        var info: [String: Any] = ["event": event.id, "session": event.sessionId]
        if let key = alert.findingKey {
            info["key"] = key
        }
        if let cwd = event.cwd, !cwd.isEmpty {
            info["cwd"] = cwd
        }
        content.userInfo = info
        content.categoryIdentifier = info["cwd"] == nil
            ? LiveMonitor.findingNoProjectCategory : LiveMonitor.findingCategory
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func notifySummary(extra: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Trailwarden"
        content.body = LocalizationStore.current.format(.liveMoreFindings, extra)
        content.userInfo = ["inbox": true]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
