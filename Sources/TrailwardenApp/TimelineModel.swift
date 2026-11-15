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

    var id: String { rawValue }

    var label: String {
        let localizer = LocalizationStore.current
        switch self {
        case .day: return localizer.text(.today)
        case .week: return localizer.text(.last7Days)
        case .month: return localizer.text(.last30Days)
        case .everything: return localizer.text(.allTime)
        }
    }

    var since: Date? {
        switch self {
        case .day: Calendar.current.startOfDay(for: Date())
        case .week: Date().addingTimeInterval(-7 * 86_400)
        case .month: Date().addingTimeInterval(-30 * 86_400)
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

    @Published var selection: TimelineSelection = .all { didSet { reload() } }
    @Published var window: TimelineWindow = .month { didSet { reload() } }
    @Published var agentFilter: Agent? { didSet { reload() } }
    @Published var findingsOnly = false { didSet { reload() } }
    /// Token counters and session markers are hidden unless asked for.
    @Published var showRawEvents = false { didSet { reload() } }
    @Published var search = "" { didSet { scheduleSearch() } }

    @Published var selectedEventID: String?
    @Published private(set) var events: [Event] = []
    @Published private(set) var total = 0
    @Published private(set) var projects: [ProjectSummary] = []
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var store: EventStore?
    private var searchTask: Task<Void, Never>?

    init(databaseURL: URL) {
        do {
            store = try EventStore(url: databaseURL)
        } catch {
            errorMessage = String(describing: error)
        }
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
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
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
            errorMessage = String(describing: error)
        }
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
        case .session(let id): return sessions.filter { $0.id == id }
        case .project(let cwd): return sessions(inProject: cwd)
        case .all: return []
        }
    }

    var selectionTitle: String {
        switch selection {
        case .all: return LocalizationStore.current.text(.allSessions)
        case .project(let cwd): return ProjectName.short(cwd)
        case .session(let id): return Sessions.shortID(id)
        }
    }

    // MARK: - Query

    private func makeQuery(offset: Int, paged: Bool = true) -> EventQuery {
        var query = EventQuery()
        query.since = window.since
        if let agentFilter { query.agents = [agentFilter] }
        if findingsOnly { query.onlyFindings = true }
        if !showRawEvents { query.excludedKinds = [.tokenUsage, .sessionStart] }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { query.search = trimmed }
        switch selection {
        case .all: break
        case .project(let cwd): query.projects = [cwd]
        case .session(let id): query.sessionIDs = [id]
        }
        if paged {
            query.limit = Self.pageSize
            query.offset = offset
        }
        return query
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
