// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import UserNotifications

/// Window and appearance setup that must happen after NSApplication exists.
/// Doing this in `App.init()` traps, because `NSApp` is still nil there.
@MainActor
final class TrailwardenDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Live-guard notifications open the event they are about.
        UNUserNotificationCenter.current().delegate = self
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

    // MARK: - Notifications

    /// Show the banner even while a Trailwarden window is in front: a critical
    /// command is news wherever the reader is looking.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void)
    {
        let info = response.notification.request.content.userInfo
        // An update notice opens the release page; a finding opens the event.
        if let link = (info["url"] as? String).flatMap(URL.init(string:)) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(link)
            }
            completionHandler()
            return
        }
        let session = info["session"] as? String
        let event = info["event"] as? String
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .trailwardenOpenEvent,
                object: nil,
                userInfo: ["session": session as Any, "event": event as Any])
        }
        completionHandler()
    }
}
