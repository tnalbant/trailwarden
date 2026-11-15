// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Renders a `UIString` in one language.
///
/// The English table is the reference: if a translation forgets a key the
/// English text is shown, never the enum case name, and a test walks every key
/// in every language so a forgotten one fails the build instead of shipping.
public struct Localizer: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language == .system ? .english : language
    }

    public init(chosen: AppLanguage, preferred: [String] = Locale.preferredLanguages) {
        self.init(language: AppLanguage.resolve(chosen, preferred: preferred))
    }

    /// The locale to format dates and numbers with.
    public var locale: Locale {
        Locale(identifier: language.rawValue)
    }

    public func text(_ key: UIString) -> String {
        Self.table(for: language)[key] ?? UITranslations.english[key] ?? key.rawValue
    }

    /// A format string with arguments, e.g. `format(.eventCount, 12)`.
    public func format(_ key: UIString, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// Severity words are lower-case inside a sentence and capitalised as a
    /// label; the table holds the sentence form.
    public func severity(_ severity: Severity) -> String {
        text(severity.uiKey)
    }

    static func table(for language: AppLanguage) -> [UIString: String] {
        switch language {
        case .system, .english: UITranslations.english
        case .turkish: UITranslations.turkish
        case .german: UITranslations.german
        case .spanish: UITranslations.spanish
        case .italian: UITranslations.italian
        case .french: UITranslations.french
        }
    }
}

public extension Severity {
    var uiKey: UIString {
        switch self {
        case .critical: .severityCritical
        case .warn: .severityWarning
        case .info: .severityInfo
        }
    }
}

/// Where the choice lives: one defaults key, read through `current` on every
/// render so a change of language redraws without a restart.
public enum LocalizationStore {
    public static let defaultsKey = "trailwarden.language"

    public static var chosen: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let language = AppLanguage(rawValue: raw) else { return .system }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    public static var current: Localizer {
        Localizer(chosen: chosen)
    }
}
