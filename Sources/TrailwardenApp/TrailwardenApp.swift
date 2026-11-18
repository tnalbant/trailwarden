// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import Darwin
import SwiftUI
import TrailwardenCore

@main
struct TrailwardenApp: App {
    @StateObject private var model = AppModel()
    /// One checker for the whole app, so a check started at launch and a check
    /// started from the panel are the same result.
    @StateObject private var updates = UpdateChecker()

    @NSApplicationDelegateAdaptor(TrailwardenDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model, updates: updates)
        } label: {
            MenuBarLabel(model: model, updates: updates)
        }
        .menuBarExtraStyle(.window)

        Window("Trailwarden", id: "main") {
            MainWindowView(model: model)
        }
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentMinSize)

        Window(L(.windowReport), id: "report") {
            ReportView(model: model)
        }
        .defaultSize(width: 860, height: 760)
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
            SettingsView(model: model, updates: updates)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

/// The menu bar item: a shield, plus today's critical count when there is one.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    /// Observed, not passed by value: the label owns `openWindow`, and a counter
    /// it cannot see changing would never open anything.
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "shield.lefthalf.filled")
            if model.snapshot.criticalToday > 0 {
                Text("\(model.snapshot.criticalToday)")
            }
        }
        // The label exists for the whole life of the app, so it owns the update
        // schedule. With the default (never) this starts nothing.
        .task {
            updates.startSchedule()
        }
        // A clicked notification asks for the window; the label is always on
        // screen, so it is the one view that can open it at any time.
        .onChange(of: model.windowRequested) { _, _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        #if DEBUG
        // Screenshots and UI checks need the window without a hand on the mouse;
        // release builds never see this.
        .task {
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_MAIN"] == "1" {
                openWindow(id: "main")
            }
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_REPORT"] == "1" {
                openWindow(id: "report")
            }
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_USAGE"] == "1" {
                openWindow(id: "usage")
            }
            if ProcessInfo.processInfo.environment["TRAILWARDEN_CHECK_UPDATES"] == "1" {
                await updates.check()
                print("[updates] state=\(updates.state)")
                fflush(stdout)
            }
            if let path = ProcessInfo.processInfo.environment["TRAILWARDEN_SNAPSHOT_REPORT"],
               let store = try? EventStore(url: model.databaseURL),
               let card = try? ReportCard.build(from: store)
            {
                let renderer = ImageRenderer(
                    content: ReportView(model: model, preloaded: card, scrolls: false)
                        .frame(width: 860))
                renderer.scale = 2
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:])
                {
                    try? png.write(to: URL(fileURLWithPath: path))
                    print("[snapshot] \(path)")
                    fflush(stdout)
                }
            }
            if let path = ProcessInfo.processInfo.environment["TRAILWARDEN_SNAPSHOT_PANEL"] {
                // The menu bar panel cannot be opened from a script, so its contents
                // are rendered straight to a PNG for a visual check. Debug only, and
                // after the check so the line it produces is in the picture.
                try? await Task.sleep(for: .seconds(1))
                let renderer = ImageRenderer(
                    content: MenuBarView(model: model, updates: updates)
                        .frame(width: Tokens.Metrics.panelWidth)
                        .background(Tokens.Palette.paper))
                renderer.scale = 2
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:])
                {
                    try? png.write(to: URL(fileURLWithPath: path))
                    print("[snapshot] \(path)")
                    fflush(stdout)
                }
            }
        }
        #endif
    }
}
