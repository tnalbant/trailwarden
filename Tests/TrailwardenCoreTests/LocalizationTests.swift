// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

/// The translation tables are data, and data goes missing quietly: a key added
/// to English and forgotten in four other languages shows as an English sentence
/// in a German window, which is exactly the kind of thing nobody notices.
final class LocalizationTests: XCTestCase {
    private let languages = AppLanguage.translated

    func testEveryKeyIsTranslatedEverywhere() {
        for language in languages {
            let table = Localizer.table(for: language)
            let missing = UIString.allCases.filter { table[$0] == nil }
            XCTAssertTrue(
                missing.isEmpty,
                "\(language.rawValue) misses \(missing.map(\.rawValue))"
            )
        }
    }

    func testNoTranslationIsBlank() {
        for language in languages {
            let table = Localizer.table(for: language)
            for key in UIString.allCases {
                let value = try? XCTUnwrap(table[key])
                XCTAssertFalse(
                    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue)/\(key.rawValue) is blank"
                )
            }
        }
    }

    func testFormatSpecifiersMatchEnglish() {
        // A translation that drops a %d crashes String(format:) at runtime, and a
        // translation that adds one prints garbage; the count has to agree.
        for language in languages where language != .english {
            let table = Localizer.table(for: language)
            for key in UIString.allCases {
                let reference = Self.specifiers(in: UITranslations.english[key] ?? "")
                let translated = Self.specifiers(in: table[key] ?? "")
                XCTAssertEqual(
                    reference, translated,
                    "\(language.rawValue)/\(key.rawValue) has \(translated) instead of \(reference)"
                )
            }
        }
    }

    func testNoTurkishLettersLeakIntoOtherLanguages() {
        // ı, ğ, ş are Turkish-only in practice; a German or French sentence that
        // carries one came from a copy-paste, not a translation.
        let turkishOnly = CharacterSet(charactersIn: "ığşİ")
        for language in languages where language != .turkish {
            let table = Localizer.table(for: language)
            for key in UIString.allCases {
                let value = table[key] ?? ""
                XCTAssertNil(
                    value.rangeOfCharacter(from: turkishOnly),
                    "\(language.rawValue)/\(key.rawValue) still carries Turkish letters: \(value)"
                )
            }
        }
    }

    func testEnglishIsTheFallbackForUnknownKeys() {
        let localizer = Localizer(language: .english)
        XCTAssertEqual(localizer.text(.today), "Today")
        XCTAssertEqual(localizer.format(.eventCount, 3), "3 events")
    }

    func testEveryRuleIsTranslatedInEveryLanguage() {
        let ids = ["R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10"]
        for id in ids {
            for language in languages {
                let text = RuleLocalization.text(forRule: id, language: language)
                XCTAssertNotNil(text, "\(id) has no \(language.rawValue) text")
                XCTAssertFalse(text?.title.isEmpty ?? true, "\(id)/\(language.rawValue) title")
                XCTAssertFalse(text?.message.isEmpty ?? true, "\(id)/\(language.rawValue) message")
            }
        }
    }

    func testRuleTextDiffersBetweenLanguages() {
        // A title copied across languages without translating it is the failure
        // mode this catches: German must not be identical to English for all rules.
        let english = (1...10).compactMap {
            RuleLocalization.text(forRule: "R\($0)", language: .english)?.title
        }
        let german = (1...10).compactMap {
            RuleLocalization.text(forRule: "R\($0)", language: .german)?.title
        }
        XCTAssertEqual(english.count, 10)
        XCTAssertEqual(german.count, 10)
        XCTAssertNotEqual(english, german)
    }

    func testTheCatalogueRulesCarryTranslations() throws {
        // Read the shipped file rather than a copy: this is the one that ends up
        // in the app bundle, and a rule added there must not ship untranslated.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TrailwardenCore/Resources/rules.json")
        let rules = try RuleCatalog.load(from: url)
        for rule in rules {
            XCTAssertNotNil(
                RuleLocalization.text(forRule: rule.id, language: .german),
                "\(rule.id) is in rules.json but has no German text"
            )
        }
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["de-AT"]), .german)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["tr"]), .turkish)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["es-419"]), .spanish)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["it-IT"]), .italian)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["fr-CA"]), .french)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["pt-BR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: []), .english)
        XCTAssertEqual(AppLanguage.resolve(.german, preferred: ["tr-TR"]), .german)
    }

    func testStoredChoiceWinsAndRoundTrips() {
        let store = LocalizationStore.defaultsKey
        let previous = UserDefaults.standard.string(forKey: store)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: store) }
            else { UserDefaults.standard.removeObject(forKey: store) }
        }

        LocalizationStore.chosen = .french
        XCTAssertEqual(LocalizationStore.chosen, .french)
        XCTAssertEqual(LocalizationStore.current.language, .french)
        XCTAssertEqual(LocalizationStore.current.text(.today), "Aujourd'hui")
    }

    func testSeverityWordsAreLocalised() {
        for language in languages {
            let localizer = Localizer(language: language)
            for severity in [Severity.critical, .warn, .info] {
                XCTAssertFalse(localizer.severity(severity).isEmpty)
            }
        }
    }

    // MARK: - Helper

    private static func specifiers(in text: String) -> [String] {
        // "%d", "%@", "%.2f" — capture the conversion but not the width/precision.
        var found: [String] = []
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            guard chars[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            while cursor < chars.count, "0123456789.-".contains(chars[cursor]) { cursor += 1 }
            if cursor < chars.count { found.append("%" + String(chars[cursor])) }
            index = cursor + 1
        }
        return found
    }
}
