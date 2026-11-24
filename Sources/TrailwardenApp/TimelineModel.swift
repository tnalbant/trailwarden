// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// What the sidebar has selected.
enum TimelineSelection: Hashable {
    case all
    case project(String)
    case session(String)
}

/// Preset time windows in the filter bar.
enum TimelineWindow: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case everything

    var id: String {
        rawValue
    }

    var label: String {
        let localizer = LocalizationStore.current
        switch self {
        case .day: return localizer.text(.today)
        case .week: return localizer.text(.last7Days)
        case .month: return localizer.text(.last30Days)
        case .everything: return localizer.text(.allTime)
        }
    }

    /// A popup button label that fits beside four other controls.
    var shortLabel: String {
        let localizer = LocalizationStore.current
        switch self {
        case .day: return localizer.text(.rangeDay)
        case .week: return localizer.text(.rangeWeek)
        case .month: return localizer.text(.rangeMonth)
        case .everything: return localizer.text(.rangeAll)
        }
    }

    var since: Date? {
        switch self {
        case .day: Calendar.current.startOfDay(for: Date())
        case .week: Date().addingTimeInterval(-7 * 86400)
        case .month: Date().addingTimeInterval(-30 * 86400)
        case .everything: nil
        }
    }
}

/// Paged event list behind the timeline. Every query runs on the main actor
/// against one connection; a page is 200 rows, which keeps the first paint fast
/// on the 24k-event index this machine produces.
@MainActor
final class TimelineModel: ObservableObject {
    static let pageSize = 200

    @Published var selection: TimelineSelection = .all {
        didSet { reload() }
    }

    @Published var window: TimelineWindow = .month {
        didSet { reload() }
    }

    @Published var agentFilter: Agent? {
        didSet { reload() }
    }

    @Published var findingsOnly = false {
        didSet { reload() }
    }

    /// Token counters and session markers are hidden unless asked for.
    @Published var showRawEvents = false {
        didSet { reload() }
    }

    @Published var search = "" {
        didSet {
            guard search != oldValue else { return }
            scheduleSearch()
        }
    }

    @Published var selectedEventID: String?
    @Published private(set) var events: [Event] = []
    @Published private(set) var total = 0
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var store: EventStore?
    private var searchTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?

    /// Set once a revealed event is in the loaded page; the list scrolls to it.
    @Published private(set) var scrollTarget: String?

    let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        do {
            store = try EventStore(url: databaseURL)
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
        #if DEBUG
            if ProcessInfo.processInfo.environment["TRAILWARDEN_SELECT_FINDING"] == "1" {
                findingsOnly = true
            }
        #endif
        reload()
    }

    // MARK: - Loading

    func reload() {
        guard let store else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try store.projects()
            sessions = try store.sessions()
            total = try store.eventCount(matching: makeQuery(offset: 0, paged: false))
            events = try store.events(matching: makeQuery(offset: 0))
            // Open on something rather than an empty panel; a selection the user
            // made and that is still in the page survives a reload.
            if selectedEventID == nil || !events.contains(where: { $0.id == selectedEventID }) {
                selectedEventID = events.first?.id
                #if DEBUG
                    // Screenshots open on a finding, so the inspector shows a rule.
                    if ProcessInfo.processInfo.environment["TRAILWARDEN_SELECT_FINDING"] == "1",
                       let finding = events.first(where: { !$0.risk.isEmpty })
                    {
                        selectedEventID = finding.id
                    }
                #endif
            }
            errorMessage = nil
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }

    func loadMore() {
        guard let store, events.count < total, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let more = try store.events(matching: makeQuery(offset: events.count))
            events.append(contentsOf: more)
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }

    /// Selects an event from a deep link, loading further pages until it is in
    /// the list (at most 20 pages). A page per main-actor turn keeps the UI live.
    func reveal(_ eventID: String) {
        revealTask?.cancel()
        // A debounced search reload would reset the page and drop the selection.
        searchTask?.cancel()
        scrollTarget = nil
        revealTask = Task { [weak self] in
            for _ in 0 ..< 20 {
                guard let self, !Task.isCancelled else { return }
                if events.contains(where: { $0.id == eventID }) {
                    break
                }
                guard events.count < total else {
                    return
                }
                loadMore()
                await Task.yield()
            }
            guard let self, !Task.isCancelled,
                  events.contains(where: { $0.id == eventID }) else { return }
            selectedEventID = eventID
            scrollTarget = eventID
        }
    }

    /// Called once the list has scrolled, so a later remount does not scroll again.
    func consumeScrollTarget() {
        scrollTarget = nil
    }

    func sessions(inProject cwd: String) -> [SessionSummary] {
        sessions
            .filter { $0.cwd == cwd }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var selectedEvent: Event? {
        guard let selectedEventID else { return nil }
        return events.first { $0.id == selectedEventID }
    }

    var filteredSessions: [SessionSummary] {
        switch selection {
        case let .session(id): sessions.filter { $0.id == id }
        case let .project(cwd): sessions(inProject: cwd)
        case .all: []
        }
    }

    /// What the reader is looking at, in words: "All sessions", a folder name, or
    /// "Session local-ed…8120" — never a bare id floating in the row.
    var selectionLabel: String {
        switch selection {
        case .all: LocalizationStore.current.text(.allSessions)
        case let .project(cwd): ProjectName.short(cwd)
        case let .session(id):
            LocalizationStore.current.text(.labelSession) + " " + Sessions.shortID(id)
        }
    }

    var selectionIcon: String {
        switch selection {
        case .all: "tray.full"
        case .project: "folder"
        case .session: "clock.arrow.circlepath"
        }
    }

    var selectionTitle: String {
        switch selection {
        case .all: LocalizationStore.current.text(.allSessions)
        case let .project(cwd): ProjectName.short(cwd)
        case let .session(id): Sessions.shortID(id)
        }
    }

    // MARK: - Query

    private func makeQuery(offset: Int, paged: Bool = true) -> EventQuery {
        var query = EventQuery()
        query.since = window.since
        if let agentFilter {
            query.agents = [agentFilter]
        }
        if findingsOnly {
            query.onlyFindings = true
        }
        if !showRawEvents {
            query.excludedKinds = [.tokenUsage, .sessionStart]
        }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.search = trimmed
        }
        switch selection {
        case .all: break
        case let .project(cwd): query.projects = [cwd]
        case let .session(id): query.sessionIDs = [id]
        }
        if paged {
            query.limit = Self.pageSize
            query.offset = offset
        }
        return query
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        // Searching is a question about everything, but the field sits next to a
        // project or session someone picked earlier. Left alone, the query runs
        // inside that selection and answers "nothing found" — which reads as a
        // broken search rather than a narrow filter.
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if case .all = selection {} else {
                selection = .all
            }
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
