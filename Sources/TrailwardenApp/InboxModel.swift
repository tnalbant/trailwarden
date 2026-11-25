// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// The findings waiting for a decision, and the decisions a reader can make.
@MainActor
final class InboxModel: ObservableObject {
    @Published private(set) var findings: [InboxFinding] = []
    @Published private(set) var backlog: Int?
    @Published private(set) var expiringClaudeSessions = 0
    @Published var errorMessage: String?

    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        reload()
    }

    func reload() {
        do {
            let snapshot = try Inbox.load(
                from: EventStore(url: databaseURL),
                claudeSettingsURL: ClaudeCleanup.defaultSettingsURL)
            findings = snapshot.unreviewed
            backlog = snapshot.backlog
            expiringClaudeSessions = snapshot.expiringClaudeSessions
            errorMessage = nil
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }

    func review(_ finding: InboxFinding, as state: ReviewState) {
        do {
            try EventStore(url: databaseURL).setReview(state, for: finding.id)
            reload()
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }

    func resolveBacklog(markReviewed: Bool) {
        do {
            try Inbox.resolveBacklog(EventStore(url: databaseURL), markReviewed: markReviewed)
            reload()
        } catch {
            errorMessage = TechnicalDetails.errorText(error)
        }
    }
}
