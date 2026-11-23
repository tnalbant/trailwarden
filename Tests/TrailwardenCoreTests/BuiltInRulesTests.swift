// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// The rules are edited in `Resources/rules.json` and compiled in through
/// `scripts/embed-rules.py`. If someone edits one and not the other, this fails.
final class BuiltInRulesTests: XCTestCase {
    func testTheEmbeddedRulesMatchRulesJSON() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TrailwardenCore/Resources/rules.json")
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(
            BuiltInRules.json,
            onDisk,
            "rules.json changed: run `python3 scripts/embed-rules.py`")
    }

    func testTheBuiltInCatalogLoadsWithoutAResourceBundle() throws {
        let rules = try RuleCatalog.builtIn()
        XCTAssertEqual(rules.count, 28, "R28 was added in 0.2.5")
        XCTAssertEqual(rules.first?.id, "R1")
    }
}
