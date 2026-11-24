// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class RulePreferencesTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tw-prefs-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testSaveLoadRoundTrip() throws {
        let prefs = [
            RulePreference(id: "R3", enabled: false, severity: .warn),
            RulePreference(id: "R1", enabled: true, severity: .warn)
        ]

        try RulePreferences.save(prefs, to: url)
        let loaded = try RulePreferences.load(from: url)

        XCTAssertEqual(loaded, prefs.sorted { $0.id < $1.id })
        XCTAssertEqual(loaded.map(\.id), ["R1", "R3"], "the file is sorted so diffs stay small")
    }

    func testSavedFileIsOwnerOnly() throws {
        try RulePreferences.save([RulePreference(id: "R1", enabled: true, severity: .critical)], to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertEqual(mode.intValue & 0o777, 0o600)
    }

    func testMissingFileMeansNoPreferences() throws {
        XCTAssertEqual(try RulePreferences.load(from: url), [])
    }

    func testUserSeverityOverrideSurvivesPatternChange() throws {
        let rules = try RuleCatalog.builtIn()

        let prefs = [RulePreference(id: "R7", enabled: true, severity: .warn)]

        let applied = RulePreferences.apply(prefs, to: rules)

        let r7 = try XCTUnwrap(applied.first { $0.id == "R7" })
        XCTAssertEqual(r7.severity, .warn)
        XCTAssertTrue(r7.isEnabled)
    }

    func testApplyTouchesOnlyKnownRules() throws {
        let rules = try RuleCatalog.builtIn()
        let prefs = [
            RulePreference(id: "R1", enabled: false, severity: .warn),
            RulePreference(id: "RX", enabled: false, severity: .info)
        ]

        let applied = RulePreferences.apply(prefs, to: rules)

        let r1 = try XCTUnwrap(applied.first { $0.id == "R1" })
        XCTAssertFalse(r1.isEnabled)
        XCTAssertEqual(r1.severity, .warn)
        XCTAssertEqual(applied.count, rules.count, "an unknown id cannot add or drop a rule")

        let r2 = try XCTUnwrap(applied.first { $0.id == "R2" })
        XCTAssertTrue(r2.isEnabled, "untouched rules keep their shipped values")
    }

    func testRoundTripsThroughRuleList() throws {
        let rules = try RuleCatalog.builtIn()
        let edited = rules.map { rule in
            rule.id == "R9" ? rule.with(enabled: false, severity: .info) : rule
        }

        let prefs = RulePreferences.preferences(from: edited)
        let restored = RulePreferences.apply(prefs, to: rules)

        XCTAssertEqual(prefs.count, rules.count)
        let r9 = try XCTUnwrap(restored.first { $0.id == "R9" })
        XCTAssertFalse(r9.isEnabled)
        XCTAssertEqual(r9.severity, .info)
        XCTAssertEqual(restored.first { $0.id == "R1" }?.severity, rules.first { $0.id == "R1" }?.severity)
    }
}
