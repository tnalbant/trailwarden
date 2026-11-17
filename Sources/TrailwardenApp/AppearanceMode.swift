// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import TrailwardenCore

/// Follow the system, or pin one appearance. Stored as a string so the choice
/// survives restarts and can be changed from Settings or `defaults write`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "trailwarden.appearance"

    var id: String {
        rawValue
    }

    var label: String {
        let localizer = LocalizationStore.current
        switch self {
        case .system: return localizer.text(.appearanceAutomatic)
        case .light: return localizer.text(.appearanceLight)
        case .dark: return localizer.text(.appearanceDark)
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// `NSApp` belongs to the main actor; both callers (the delegate and the
    /// Settings picker) are already there.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }

    @MainActor
    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppearanceMode.system.rawValue
        (AppearanceMode(rawValue: raw) ?? .system).apply()
    }
}
