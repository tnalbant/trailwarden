// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class RetentionChoiceTests: XCTestCase {
    func testUnknownOrMissingStoredValueIsForever() {
        XCTAssertEqual(RetentionChoice.resolve(stored: nil), .forever)
        XCTAssertEqual(RetentionChoice.resolve(stored: ""), .forever)
        XCTAssertEqual(RetentionChoice.resolve(stored: "30"), .forever)
        XCTAssertEqual(RetentionChoice.resolve(stored: "oneYear"), .oneYear)
        XCTAssertEqual(RetentionChoice.resolve(stored: "ninetyDays"), .ninetyDays)
    }

    func testDays() {
        XCTAssertNil(RetentionChoice.forever.days)
        XCTAssertEqual(RetentionChoice.oneYear.days, 365)
        XCTAssertEqual(RetentionChoice.ninetyDays.days, 90)
        XCTAssertEqual(RetentionChoice.storageKey, "trailwarden.retention")
    }
}
