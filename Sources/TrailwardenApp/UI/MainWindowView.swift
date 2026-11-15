// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The window the menu bar opens: sidebar plus the timeline.
struct MainWindowView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @StateObject private var timeline: TimelineModel

    init(model: AppModel) {
        self.model = model
        _timeline = StateObject(wrappedValue: TimelineModel(databaseURL: model.databaseURL))
    }

    var body: some View {
        TimelineView(model: timeline, onMute: { hit, event in
            let target = RuleEngine.target(for: event)
            Task {
                await model.mute(ruleId: hit.ruleId, target: target)
                timeline.reload()
            }
        }, liveSessionIDs: model.liveSessions)
            .frame(minWidth: 780, minHeight: 480)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await model.scan()
                            timeline.reload()
                        }
                    } label: {
                        Label(
                            model.isScanning ? L(.scanning) : L(.rescan),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(model.isScanning)
                }
            }
    }
}
