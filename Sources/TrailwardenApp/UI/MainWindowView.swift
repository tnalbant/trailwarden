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
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text(L(.todayFeed)).tag(Mode.feed)
                Text(L(.timelineTab)).tag(Mode.timeline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .padding(.top, 8)
            .padding(.bottom, 6)

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

    private var timelineView: some View {
        TimelineView(model: timeline, onMute: { hit, event in
            let target = RuleEngine.target(for: event)
            Task {
                await model.mute(ruleId: hit.ruleId, target: target)
                timeline.reload()
            }
        }, liveSessionIDs: model.liveSessions)
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
