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
        .frame(minWidth: 780, minHeight: 480)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .task {
            #if DEBUG
                switch ProcessInfo.processInfo.environment["TRAILWARDEN_SELECT_FIRST"] {
                case "1":
                    try? await Task.sleep(for: .seconds(1))
                    timeline.selectedEventID = timeline.events.first?.id
                case "tool":
                    try? await Task.sleep(for: .seconds(1))
                    timeline.selectedEventID = timeline.events.first { $0.command != nil }?.id
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
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await model.scan()
                        timeline.reload()
                        feed.reload()
                    }
                } label: {
                    Label(
                        model.isScanning ? L(.scanning) : L(.rescan),
                        systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        timeline.window = .day
        timeline.findingsOnly = true
        mode = .timeline
    }

    /// Jumping to a session always means the timeline: the feed is a digest, the
    /// timeline is the record. The range widens first, or an older session would
    /// be filtered out by the current preset.
    private func open(_ sessionID: String) {
        timeline.window = .everything
        timeline.selection = .session(sessionID)
        mode = .timeline
    }
}
