// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The window the menu bar opens: what happened today, with the full timeline
/// one click away.
struct MainWindowView: View {
    /// Two answers to the same question at different zoom levels: the feed says
    /// what happened, the timeline lets you dig into one session.
    private enum Mode: String, CaseIterable, Identifiable {
        case feed
        case timeline

        var id: String {
            rawValue
        }
    }

    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @StateObject private var timeline: TimelineModel
    @StateObject private var feed: FeedModel
    @State private var mode: Mode = .feed
    @FocusState private var searchFocused: Bool

    init(model: AppModel) {
        self.model = model
        _timeline = StateObject(wrappedValue: TimelineModel(databaseURL: model.databaseURL))
        _feed = StateObject(wrappedValue: FeedModel(databaseURL: model.databaseURL))
        #if DEBUG
            // UI checks need to land on a given screen without a hand on the mouse.
            // Release builds never see this.
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_MODE"] == "timeline" {
                _mode = State(initialValue: .timeline)
            }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            chrome
            Hairline()
            switch mode {
            case .feed:
                FeedView(model: feed) { sessionID in
                    open(sessionID)
                }
            case .timeline:
                timelineView
            }
        }
        // Three columns need 200 + 400 + 340 plus two dividers. Below that the
        // split view squeezed them and the panes clipped their own content — the
        // sidebar cut on the left, timestamps losing their first digit.
        .frame(minWidth: 960, minHeight: 520)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .task {
            #if DEBUG
                let environment = ProcessInfo.processInfo.environment
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
        .onChange(of: model.sessionToOpen) { _, sessionID in
            guard let sessionID else { return }
            open(sessionID)
            model.sessionToOpen = nil
            if let eventID = model.eventToSelect {
                timeline.selectedEventID = eventID
                model.eventToSelect = nil
            }
        }
        .onAppear {
            // A notification clicked while the window was closed: the request
            // arrived before this view existed to observe it.
            if let sessionID = model.sessionToOpen {
                open(sessionID)
                model.sessionToOpen = nil
                if let eventID = model.eventToSelect {
                    timeline.selectedEventID = eventID
                    model.eventToSelect = nil
                }
            }
        }
    }

    /// One header for both modes, so the feed and the timeline read as the same
    /// application rather than two screens that happen to share a window.
    private var chrome: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Picker("", selection: $mode) {
                Text(L(.todayFeed)).tag(Mode.feed)
                Text(L(.timelineTab)).tag(Mode.timeline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            if mode == .timeline {
                HStack(spacing: 5) {
                    Image(systemName: timeline.selectionIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.Palette.tertiary)
                    Text(timeline.selectionLabel)
                        .font(Tokens.Typography.text(11, weight: .medium))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1)
                }
                .help(selectionHelp)
            }

            if mode == .timeline {
                searchField
            }

            Spacer()

            if model.snapshot.criticalToday > 0 {
                Button {
                    showFindings()
                } label: {
                    HStack(spacing: 3) {
                        Text(Lf(.sessionCritical, [model.snapshot.criticalToday]))
                            .font(Tokens.Typography.text(10, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(Tokens.Palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L(.severityCritical))
            }
            Text(Lf(.eventCount, [model.snapshot.totalEvents]))
                .font(Tokens.Typography.mono(10))
                .foregroundStyle(Tokens.Palette.secondary)

            Button {
                Task {
                    await model.scan()
                    timeline.reload()
                    feed.reload()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isScanning)
            .help(model.isScanning ? L(.scanning) : L(.rescan))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                .font(Tokens.Typography.text(11))
                .focused($searchFocused)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Tokens.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .frame(minWidth: 140, idealWidth: 200, maxWidth: 240)
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

    private var timelineView: some View {
        TimelineView(model: timeline, onMute: { hit, event in
            let target = RuleEngine.target(for: event)
            Task {
                await model.mute(ruleId: hit.ruleId, target: target)
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
        mode = .timeline
    }

    /// Jumping to a session always means the timeline: the feed is a digest, the
    /// timeline is the record. The range widens first, or an older session would
    /// be filtered out by the current preset.
    private func open(_ sessionID: String) {
        // Opening a session means its whole story, so any finding/agent filter
        // from a previous visit is cleared rather than silently applied.
        timeline.findingsOnly = false
        timeline.agentFilter = nil
        timeline.search = ""
        timeline.window = .everything
        timeline.selection = .session(sessionID)
        mode = .timeline
    }
}
