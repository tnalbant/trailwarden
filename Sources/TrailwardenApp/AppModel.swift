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

    let databaseURL: URL

    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
            ?? (try? EventStore.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trailwarden.sqlite")
        self.onboardingDone = UserDefaults.standard.bool(forKey: Self.onboardingKey)
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
