// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation
import TrailwardenCore

/// The day feed: what the agents did, grouped by the project they did it in.
///
/// The timeline answers "show me everything"; this answers "what happened today",
/// which is the question a person actually opens the app with.
@MainActor
final class FeedModel: ObservableObject {
    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let items: [ActivityItem]
        let criticalCount: Int

        var latest: Date {
            items.first?.time ?? .distantPast
        }
    }

    @Published private(set) var sections: [Section] = []
    @Published private(set) var actionCount = 0
    @Published private(set) var criticalCount = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        reload()
    }

    func reload() {
        isLoading = true
        defer { isLoading = false }
        do {
            let store = try EventStore(url: databaseURL)
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let events = try store.events(matching: EventQuery(
                since: startOfDay,
                limit: 400,
                includeRawJSON: false))
            // The feed has the whole width of the window, so it can show more of
            // each command than the 330-point panel can.
            let items = ActivityDigest.items(from: events, limit: 400, detailLimit: 240)
            sections = Self.sections(from: items)
            actionCount = items.filter { !$0.isMessage }.count
            criticalCount = items.filter { $0.severity == .critical }.count
            errorMessage = nil
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }

    /// Grouped by project, newest project first. Items without a project (a
    /// chat-only session) collect under "—" rather than being hidden.
    static func sections(from items: [ActivityItem]) -> [Section] {
        let grouped = Dictionary(grouping: items) { $0.project ?? "—" }
        return grouped
            .map { key, value in
                let ordered = value.sorted { $0.time > $1.time }
                return Section(
                    id: key,
                    title: key,
                    items: ordered,
                    criticalCount: ordered.filter { $0.severity == .critical }.count)
            }
            .sorted { $0.latest > $1.latest }
    }
}
