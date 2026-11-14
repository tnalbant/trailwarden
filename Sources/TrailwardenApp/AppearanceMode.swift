// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit

/// Follow the system, or pin one appearance. Stored as a string so the choice
/// survives restarts and can be changed from Settings or `defaults write`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "trailwarden.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Otomatik"
        case .light: return "Açık"
        case .dark: return "Koyu"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func apply() {
        NSApp.appearance = nsAppearance
    }

    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppearanceMode.system.rawValue
        (AppearanceMode(rawValue: raw) ?? .system).apply()
    }
}
