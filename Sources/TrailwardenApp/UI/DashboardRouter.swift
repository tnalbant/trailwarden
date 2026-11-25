// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import SwiftUI

/// The sections of the one window. Every menu bar action lands on a tab instead
/// of opening a window of its own, so there is still exactly one place where the
/// story is told.
enum DashboardTab: String, CaseIterable, Identifiable {
    case inbox
    case timeline
    case report
    case usage
    case rules
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .inbox: L(.inboxTab)
        case .timeline: L(.timelineTab)
        case .report: L(.windowReport)
        case .usage: L(.windowUsage)
        case .rules: L(.windowRules)
        case .settings: L(.windowSettings)
        }
    }

    /// The five sections the View menu offers with ⌘1…⌘5. Settings keeps ⌘,.
    static var menuTabs: [DashboardTab] {
        [.inbox, .timeline, .report, .usage, .rules]
    }
}

/// Which tab the window is on, shared by the window, the menu bar panel and the
/// menu commands. Whoever asks for a section sets it here and opens the window.
@MainActor
final class DashboardRouter: ObservableObject {
    @Published var tab: DashboardTab = .inbox
    /// Bumped on every request so a window that is already open still reacts when
    /// the same section is asked for twice.
    @Published private(set) var requests = 0

    func show(_ tab: DashboardTab) {
        self.tab = tab
        requests += 1
    }
}
