// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
@testable import TrailwardenCore
import XCTest

final class StampTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testTodayShowsOnlyTheTime() {
        let now = Date()
        let stamp = ActivityDigest.stamp(now, now: now, locale: english)
        XCTAssertNotNil(
            stamp.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression),
            "bugünün damgası yalnız saat olmalı: \(stamp)")
    }

    func testAnotherDayShowsTheDate() {
        let now = Date()
        let older = now.addingTimeInterval(-86400 * 3)
        let stamp = ActivityDigest.stamp(older, now: now, locale: english)
        XCTAssertGreaterThan(stamp.count, 5, "tarih bekleniyordu: \(stamp)")
        XCTAssertTrue(stamp.contains(":"), "saat bekleniyordu: \(stamp)")
        XCTAssertNotNil(
            stamp.range(of: "[A-Za-z]{3}", options: .regularExpression),
            "ay adı bekleniyordu: \(stamp)")
    }

    func testYesterdayIsNotToday() throws {
        let now = Date()
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: now))
        XCTAssertGreaterThan(
            ActivityDigest.stamp(yesterday, now: now, locale: english).count, 5)
    }
}
