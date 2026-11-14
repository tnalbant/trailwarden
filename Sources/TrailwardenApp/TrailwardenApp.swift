// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

@main
struct TrailwardenApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Two windows (panel, rules) must not merge into a tab group.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

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
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentMinSize)

        Window("Kurallar", id: "rules") {
            RulesView(model: model)
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentMinSize)

        Window("Ayarlar", id: "settings") {
            SettingsView(model: model)
        }
        .defaultSize(width: 640, height: 560)
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
