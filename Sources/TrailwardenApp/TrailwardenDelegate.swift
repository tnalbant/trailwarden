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
        // broken. The activation policy follows the windows instead: a window on
        // screen, minimised or in a hidden app keeps the Dock tile (that is how
        // every Mac app behaves); closing the last one gives it back.
        //
        // `willClose` is posted while the closing window is still `isVisible`, so
        // the check runs again one runloop turn later — without that the app kept
        // its Dock tile forever with nothing on screen.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didBecomeKeyNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowClosed),
            name: NSWindow.willCloseNotification,
            object: nil)
    }

    /// A Dock click or ⌘-Tab on an app whose windows are all closed or minimised
    /// has to bring the dashboard back; without this the tile does nothing and
    /// the app reads as broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .trailwardenShowDashboard, object: nil)
        }
        for window in NSApp.windows where window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    @objc private func windowVisibilityChanged() {
        // Window notifications arrive on the main thread, so there is nothing to
        // hop to; a Task here would only add a race warning under Swift 6.
        MainActor.assumeIsolated { syncActivationPolicy() }
    }

    @objc private func windowClosed() {
        MainActor.assumeIsolated { syncActivationPolicy() }
        Task { @MainActor [weak self] in
            self?.syncActivationPolicy()
        }
    }

    /// `.regular` while a normal window exists (on screen, minimised or in a
    /// hidden app), `.accessory` again once the last one closes. The menu bar
    /// panel is a status-bar level window, so it is deliberately not counted.
    private func syncActivationPolicy() {
        // A hidden app (⌘H) reports its windows as not visible. Dropping the Dock
        // tile then would leave nothing to click to bring them back, so the
        // policy only changes while the app is on screen.
        guard !NSApp.isHidden else { return }
        let hasWindow = NSApp.windows.contains { window in
            (window.isVisible || window.isMiniaturized) && window.canBecomeMain && window.level == .normal
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
        let keys = info["keys"] as? [String] ?? (info["key"] as? String).map { [$0] } ?? []
        let cwd = info["cwd"] as? String
        let isInbox = info["inbox"] as? Bool ?? false
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            if isInbox {
                center.post(name: .trailwardenOpenInbox, object: nil)
            } else if action == LiveMonitor.reviewedAction || action == LiveMonitor.expectedAction {
                var answer: [String: Any] = ["action": action]
                answer["keys"] = keys
                answer["cwd"] = cwd
                center.post(name: .trailwardenFindingAnswered, object: nil, userInfo: answer)
            } else {
                center.post(
                    name: .trailwardenOpenEvent,
                    object: nil,
                    userInfo: ["session": session as Any, "event": event as Any])
            }
        }
        completionHandler()
    }
}
