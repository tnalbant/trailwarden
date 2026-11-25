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
    private var isLoading = false
    private var reloadPending = false

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
        reload()
    }

    /// Loads the inbox off the main actor; a request made while a load runs
    /// gets one more load after it instead of a second concurrent one.
    func reload() {
        reloadPending = true
        guard !isLoading else { return }
        isLoading = true
        Task { await drainReloads() }
    }

    private func drainReloads() async {
        defer { isLoading = false }
        while reloadPending {
            reloadPending = false
            let url = databaseURL
            let settings = ClaudeCleanup.defaultSettingsURL
            let loaded = await Task.detached(priority: .userInitiated) {
                Result { try Inbox.load(from: EventStore(url: url), claudeSettingsURL: settings) }
            }.value
            switch loaded {
            case let .success(snapshot):
                findings = snapshot.unreviewed
                backlog = snapshot.backlog
                expiringClaudeSessions = snapshot.expiringClaudeSessions
                errorMessage = nil
            case let .failure(error):
                errorMessage = TechnicalDetails.errorText(error)
            }
        }
    }

    func review(_ finding: InboxFinding, as state: ReviewState) {
        do {
            try EventStore(url: databaseURL).setReview(state, for: finding.id)
            // Gone at once; the reload that follows confirms it.
            findings.removeAll { $0.id == finding.id }
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
