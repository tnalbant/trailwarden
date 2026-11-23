// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import ServiceManagement
import TrailwardenCore

/// Whether Trailwarden opens when the reader logs in. The system owns the
/// answer; this only reads it and asks for a change.
@MainActor
final class LoginItem: ObservableObject {
    enum Status: Equatable {
        case enabled, disabled, requiresApproval, failed(String)
    }

    @Published private(set) var status: Status

    init() {
        status = Self.current()
    }

    /// Reads the system's answer again; the reader can change it in System Settings.
    /// A failed change stays on screen until the system says something definite:
    /// "not registered" is what a failed registration looks like, so it must not
    /// erase the explanation.
    func refresh() {
        let current = Self.current()
        if case .failed = status, current == .disabled {
            return
        }
        status = current
    }

    func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            status = Self.current()
        } catch {
            status = .failed(Lf(.loginItemFailed, [error.localizedDescription]))
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func current() -> Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }
}
