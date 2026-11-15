// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class TimeWindowTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!

    func testRelativeWindows() throws {
        XCTAssertEqual(try TimeWindow.parse("7d", now: now), now.addingTimeInterval(-7 * 86400))
        XCTAssertEqual(try TimeWindow.parse("12h", now: now), now.addingTimeInterval(-12 * 3600))
        XCTAssertEqual(try TimeWindow.parse("90m", now: now), now.addingTimeInterval(-90 * 60))
        XCTAssertEqual(try TimeWindow.parse("2w", now: now), now.addingTimeInterval(-2 * 604_800))
    }

    func testAllMeansEverything() throws {
        XCTAssertNil(try TimeWindow.parse("all", now: now))
        XCTAssertNil(try TimeWindow.parse("  ", now: now))
    }

    func testAbsoluteInstant() throws {
        let date = try XCTUnwrap(try TimeWindow.parse("2026-11-01T00:00:00Z", now: now))
        XCTAssertEqual(date.timeIntervalSince1970, 1_793_491_200, accuracy: 1)
    }

    func testInvalidInputThrows() {
        XCTAssertThrowsError(try TimeWindow.parse("yesterday", now: now))
        XCTAssertThrowsError(try TimeWindow.parse("7x", now: now))
    }
}
