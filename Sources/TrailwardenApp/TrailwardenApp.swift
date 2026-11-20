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
    /// Which tab the single window shows; shared with the menu bar panel and the
    /// menu commands so every entry point lands on the same place.
    @StateObject private var router = DashboardRouter()
    @Environment(\.openWindow) private var openWindow

    @NSApplicationDelegateAdaptor(TrailwardenDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model, updates: updates, router: router)
                .environmentObject(router)
        } label: {
            MenuBarLabel(model: model, updates: updates)
                .environmentObject(router)
        }
        .menuBarExtraStyle(.window)

        // Prices get a window of their own: the list of models is long, and
        // editing it should not push the rest of Settings out of view.
        Window(L(.pricesWindow), id: PricesWindow.id) {
            PricesWindow(book: model.priceBook, updates: updates)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)

        Window("Trailwarden", id: "main") {
            MainWindowView(model: model, updates: updates, router: router)
                .environmentObject(router)
        }
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            // Settings and the sections are tabs now, so the Window menu no
            // longer grows a row per screen and ⌘, still means "settings".
            CommandGroup(replacing: .appSettings) {
                Button(L(.windowSettings) + "…") {
                    show(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(L(.scan)) {
                    Task { await model.scan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isScanning)
            }
            CommandMenu(L(.sections)) {
                ForEach(Array(DashboardTab.menuTabs.enumerated()), id: \.element.id) { index, tab in
                    Button(tab.title) {
                        show(tab)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }

    /// Opens the window on a section, from anywhere in the app.
    private func show(_ tab: DashboardTab) {
        router.show(tab)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The menu bar item: a shield, plus today's critical count when there is one.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var router: DashboardRouter
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
                router.tab = .report
                openWindow(id: "main")
            }
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_PRICES"] == "1" {
                openWindow(id: PricesWindow.id)
            }
            if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_USAGE"] == "1" {
                router.tab = .usage
                openWindow(id: "main")
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
                        .environmentObject(router)
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
                    content: MenuBarView(model: model, updates: updates, router: router)
                        .environmentObject(router)
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
