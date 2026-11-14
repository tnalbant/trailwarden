// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The window the menu bar opens: sidebar plus the timeline.
struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @StateObject private var timeline: TimelineModel

    init(model: AppModel) {
        self.model = model
        _timeline = StateObject(wrappedValue: TimelineModel(databaseURL: model.databaseURL))
    }

    var body: some View {
        TimelineView(model: timeline)
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
                            model.isScanning ? "Taranıyor…" : "Yeniden tara",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(model.isScanning)
                }
            }
    }
}
