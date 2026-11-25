// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The one window. Every answer lives here as a tab: the day's digest, the
/// timeline that explains it, the report card, usage, the rules, the settings.
///
/// It used to be five `Window` scenes, so Settings and Rules sat in the Window
/// menu next to the dashboard and a reader had to keep track of six things.
struct MainWindowView: View {
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.standard.rawValue
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var router: DashboardRouter
    @ObservedObject var loginItem: LoginItem

    @StateObject private var timeline: TimelineModel
    @StateObject private var feed: FeedModel
    @StateObject private var inbox: InboxModel
    @FocusState private var searchFocused: Bool

    init(model: AppModel, updates: UpdateChecker, router: DashboardRouter, loginItem: LoginItem) {
        self.model = model
        self.updates = updates
        self.router = router
        self.loginItem = loginItem
        _timeline = StateObject(wrappedValue: TimelineModel(databaseURL: model.databaseURL))
        _feed = StateObject(wrappedValue: FeedModel(databaseURL: model.databaseURL))
        _inbox = StateObject(wrappedValue: InboxModel(databaseURL: model.databaseURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            content
        }
        .id(textSize)
        // Three columns need 200 + 400 + 340 plus two dividers. Below that the
        // split view squeezed them and the panes clipped their own content — the
        // sidebar cut on the left, timestamps losing their first digit.
        .frame(minWidth: 960, minHeight: 520)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .task {
            #if DEBUG
                // UI checks need to land on a given screen without a hand on the mouse.
                // Release builds never see this.
                let environment = ProcessInfo.processInfo.environment
                if environment["TRAILWARDEN_OPEN_MODE"] == "timeline" {
                    router.tab = .timeline
                }
                if environment["TRAILWARDEN_OPEN_MODE"] == "prices" {
                    router.tab = .settings
                }
                if let term = environment["TRAILWARDEN_SEARCH"], !term.isEmpty {
                    try? await Task.sleep(for: .seconds(1))
                    timeline.search = term
                }
                if environment["TRAILWARDEN_SHOW_FINDINGS"] == "1" {
                    try? await Task.sleep(for: .seconds(1))
                    showFindings()
                }
                switch environment["TRAILWARDEN_SELECT_FIRST"] {
                case "1":
                    try? await Task.sleep(for: .seconds(1))
                    if let sessionID = timeline.events.first?.sessionId {
                        open(sessionID)
                    }
                case "tool":
                    try? await Task.sleep(for: .seconds(1))
                    if let sessionID = timeline.events.first(where: { $0.command != nil })?.sessionId {
                        open(sessionID)
                    }
                default:
                    break
                }
            #endif
        }
        .onChange(of: model.findingsRequested) { _, _ in
            showFindings()
        }
        .onChange(of: model.inboxRequested) { _, _ in
            inbox.reload()
            router.tab = .inbox
        }
        .onChange(of: router.tab) { _, tab in
            if tab == .inbox {
                inbox.reload()
                feed.reload()
            }
        }
        .onChange(of: model.sessionToOpen) { _, sessionID in
            guard let sessionID else { return }
            open(sessionID, event: model.eventToSelect)
            model.sessionToOpen = nil
            model.eventToSelect = nil
        }
        .onAppear {
            // A notification clicked while the window was closed: the request
            // arrived before this view existed to observe it.
            if let sessionID = model.sessionToOpen {
                open(sessionID, event: model.eventToSelect)
                model.sessionToOpen = nil
                model.eventToSelect = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            tabBar

            if router.tab == .timeline {
                selectionLabel
                searchField
            }

            Spacer(minLength: 8)

            if model.snapshot.criticalToday > 0 {
                Button {
                    showFindings()
                } label: {
                    HStack(spacing: 3) {
                        Text(Lf(.sessionCritical, [model.snapshot.criticalToday]))
                            .font(Tokens.Typography.font(.callout, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(Tokens.Palette.accentText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L(.severityCritical))
            }
            Text(Lf(.eventCount, [model.snapshot.totalEvents]))
                .font(Tokens.Typography.font(.code))
                .foregroundStyle(Tokens.Palette.secondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)

            Button {
                Task {
                    await model.scan()
                    timeline.reload()
                    feed.reload()
                    inbox.reload()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isScanning)
            .help(model.isScanning ? model.scanLabel : L(.rescan))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// Text tabs rather than a segmented control: six segments in a fixed-width
    /// control squeezed the longer names, and Settings has no business being the
    /// sixth segment — it is a place you visit, not a way to read the day.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(DashboardTab.menuTabs) { tab in
                tabButton(tab)
            }
            Rectangle()
                .fill(Tokens.Palette.hairline)
                .frame(width: 1, height: 14)
                .padding(.horizontal, 4)
            tabButton(.settings)
        }
        .layoutPriority(2)
    }

    private func tabButton(_ tab: DashboardTab) -> some View {
        Button {
            router.tab = tab
        } label: {
            Text(tab.title)
                .font(Tokens.Typography.font(.body, weight: router.tab == tab ? .semibold : .regular))
                .foregroundStyle(router.tab == tab ? Tokens.Palette.ink : Tokens.Palette.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(router.tab == tab ? Tokens.Palette.surface : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(router.tab == tab ? .isSelected : [])
        .help(tab.title)
    }

    private var selectionLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: timeline.selectionIcon)
                .font(.system(size: 10))
                .foregroundStyle(Tokens.Palette.tertiary)
            Text(timeline.selectionLabel)
                .font(Tokens.Typography.font(.body, weight: .medium))
                .foregroundStyle(Tokens.Palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: 0)
        .help(selectionHelp)
    }

    /// The search belongs to the timeline, but it reads better in the window row
    /// than squeezed into the filter bar, where it either wrapped or clipped.
    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.Palette.tertiary)
            TextField(L(.searchPlaceholder), text: $timeline.search)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.font(.body))
                .focused($searchFocused)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Tokens.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .frame(minWidth: 90, idealWidth: 200, maxWidth: 240)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    /// The row shows a shortened id; hovering spells out what it is.
    private var selectionHelp: String {
        if case let .session(id) = timeline.selection {
            return L(.labelSession) + ": " + id
        }
        return timeline.selectionLabel
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch router.tab {
        case .inbox:
            InboxView(model: inbox, feed: feed, app: model, onOpenSession: { sessionID, eventID in
                open(sessionID, event: eventID)
            }, onOpenActivity: { item in
                open(item.sessionID, event: item.id)
            })
        case .timeline:
            timelineView
        case .report:
            ReportView(model: model)
        case .usage:
            UsageView(model: model)
        case .rules:
            RulesView(model: model)
        case .settings:
            SettingsView(model: model, updates: updates, loginItem: loginItem)
        }
    }

    private var timelineView: some View {
        TimelineView(model: timeline, onMute: { hit, event in
            let target = RuleEngine.target(for: event)
            Task {
                let now = Date()
                await model.allow(Allowance(
                    ruleId: hit.ruleId,
                    scope: .command(target),
                    until: AllowanceDuration.thirtyDays.until(from: now),
                    created: now))
                timeline.reload()
            }
        }, liveSessionIDs: model.liveSessions)
    }

    /// "2 critical" is an invitation, not a label: it opens the timeline with the
    /// finding filter on and today's range, so the two events are the only rows.
    private func showFindings() {
        // A finding view is a fresh question: today's findings across every
        // session. Leaving the previous session or search in place is how the
        // pane ended up empty and looking broken.
        timeline.selection = .all
        timeline.agentFilter = nil
        timeline.search = ""
        timeline.window = .day
        timeline.findingsOnly = true
        router.tab = .timeline
    }

    /// Jumping to a session always means the timeline: the feed is a digest, the
    /// timeline is the record. The range widens first, or an older session would
    /// be filtered out by the current preset.
    private func open(_ sessionID: String, event eventID: String? = nil) {
        // Opening a session means its whole story, so any finding/agent filter
        // from a previous visit is cleared rather than silently applied.
        timeline.findingsOnly = false
        timeline.agentFilter = nil
        timeline.search = ""
        timeline.window = .everything
        timeline.selection = .session(sessionID)
        if let eventID {
            timeline.reveal(eventID)
        }
        router.tab = .timeline
    }
}
