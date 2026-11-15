// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// The languages the interface ships in. `system` follows the Mac's preferred
/// language and falls back to English.
public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"
    case german = "de"
    case spanish = "es"
    case italian = "it"
    case french = "fr"

    public var id: String { rawValue }

    /// The name of the language in that language — the only string in this file
    /// that is deliberately not translated.
    public var endonym: String {
        switch self {
        case .system: return ""
        case .english: return "English (US)"
        case .turkish: return "Türkçe"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .french: return "Français"
        }
    }

    /// Languages that carry their own translation table (everything but `.system`).
    public static var translated: [AppLanguage] {
        allCases.filter { $0 != .system }
    }

    /// Maps a BCP-47 tag ("de-AT", "pt-BR") onto a supported language.
    public static func matching(_ identifier: String) -> AppLanguage? {
        let lower = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        let primary = lower.split(separator: "-").first.map(String.init) ?? lower
        return translated.first { $0.rawValue == primary }
    }

    /// The concrete language to render: the user's choice, or the first preferred
    /// system language we ship, or English.
    public static func resolve(_ chosen: AppLanguage, preferred: [String]) -> AppLanguage {
        if chosen != .system { return chosen }
        for identifier in preferred {
            if let match = matching(identifier) { return match }
        }
        return .english
    }
}
