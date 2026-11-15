// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

@main
struct TrailwardenApp: App {
    @StateObject private var model = AppModel()

    @NSApplicationDelegateAdaptor(TrailwardenDelegate.self) private var delegate

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

        Window(L(.windowRules), id: "rules") {
            RulesView(model: model)
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentMinSize)

        Window(L(.windowUsage), id: "usage") {
            UsageView(model: model)
        }
        .defaultSize(width: 700, height: 560)
        .windowResizability(.contentMinSize)

        Window(L(.windowSettings), id: "settings") {
            SettingsView(model: model)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

/// The menu bar item: a shield, plus today's critical count when there is one.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let criticalToday: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.lefthalf.filled")
            if criticalToday > 0 {
                Text("\(criticalToday)")
            }
        }
        #if DEBUG
        // Screenshots and UI checks need the window without a hand on the mouse;
        // release builds never see this.
        .task {
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_MAIN"] == "1" {
                openWindow(id: "main")
            }
        }
        #endif
    }
}
