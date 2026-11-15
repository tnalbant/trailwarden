// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
@testable import TrailwardenCore
import XCTest

final class StampTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testEveryStampCarriesADate() {
        let stamp = ActivityDigest.stamp(Date(), locale: english)
        XCTAssertNotNil(
            stamp.range(of: "[A-Za-z]{3}", options: .regularExpression),
            "ay adı bekleniyordu: \(stamp)")
        XCTAssertTrue(stamp.contains(":"), "saat bekleniyordu: \(stamp)")
    }

    func testYesterdayAndTodayAreDistinguishable() throws {
        let now = Date()
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: now))
        XCTAssertNotEqual(
            ActivityDigest.stamp(now, locale: english),
            ActivityDigest.stamp(yesterday, locale: english),
            "iki farklı gün aynı damgayı üretmemeli")
    }

    func testStampsAreLocalised() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotEqual(
            ActivityDigest.stamp(date, locale: Locale(identifier: "tr_TR")),
            ActivityDigest.stamp(date, locale: english))
    }
}
