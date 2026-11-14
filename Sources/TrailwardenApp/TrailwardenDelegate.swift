// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit

/// Window and appearance setup that must happen after NSApplication exists.
/// Doing this in `App.init()` traps, because `NSApp` is still nil there.
final class TrailwardenDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two windows (panel, usage, rules, settings) must not merge into a tab group.
        NSWindow.allowsAutomaticWindowTabbing = false
        AppearanceMode.applyStored()
    }
}
