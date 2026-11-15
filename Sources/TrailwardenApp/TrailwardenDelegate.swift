// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit

/// Window and appearance setup that must happen after NSApplication exists.
/// Doing this in `App.init()` traps, because `NSApp` is still nil there.
@MainActor
final class TrailwardenDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two windows (panel, usage, rules, settings) must not merge into a tab group.
        NSWindow.allowsAutomaticWindowTabbing = false
        AppearanceMode.applyStored()

        // A menu bar app has no Dock tile and no ⌘-Tab entry, which is right until
        // it opens a real window — then a window you cannot reach with ⌘-Tab feels
        // broken. The activation policy follows the windows instead.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowVisibilityChanged),
                name: name,
                object: nil)
        }
    }

    @objc private func windowVisibilityChanged() {
        // Window notifications arrive on the main thread, so there is nothing to
        // hop to; a Task here would only add a race warning under Swift 6.
        MainActor.assumeIsolated { syncActivationPolicy() }
    }

    /// `.regular` while a normal window is on screen, `.accessory` again once the
    /// last one closes. The menu bar panel is a status-bar level window, so it is
    /// deliberately not counted.
    private func syncActivationPolicy() {
        let hasWindow = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeMain && window.level == .normal
        }
        let policy: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
