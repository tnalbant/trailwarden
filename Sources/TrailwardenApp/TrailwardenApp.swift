// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

@main
struct TrailwardenApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(criticalToday: model.snapshot.criticalToday)
        }
        .menuBarExtraStyle(.window)

        Window("Trailwarden", id: "main") {
            MainWindowView(model: model)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
    }
}

/// The menu bar item: a shield, plus today's critical count when there is one.
private struct MenuBarLabel: View {
    let criticalToday: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.lefthalf.filled")
            if criticalToday > 0 {
                Text("\(criticalToday)")
            }
        }
    }
}
