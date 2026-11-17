// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class UpdateScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNeverIsNeverDue() {
        XCTAssertFalse(UpdateSchedule.never.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateSchedule.never.isDue(lastCheck: now.addingTimeInterval(-400 * 86400), now: now))
        XCTAssertNil(UpdateSchedule.never.nextCheck(after: nil, now: now))
    }

    func testAScheduleThatNeverRanIsDueAtOnce() {
        XCTAssertTrue(UpdateSchedule.weekly.isDue(lastCheck: nil, now: now))
        XCTAssertTrue(UpdateSchedule.monthly.isDue(lastCheck: nil, now: now))
    }

    func testWeeklyAndMonthlyIntervals() {
        let sixDays = now.addingTimeInterval(-6 * 86400)
        let eightDays = now.addingTimeInterval(-8 * 86400)
        XCTAssertFalse(UpdateSchedule.weekly.isDue(lastCheck: sixDays, now: now))
        XCTAssertTrue(UpdateSchedule.weekly.isDue(lastCheck: eightDays, now: now))
        XCTAssertFalse(UpdateSchedule.monthly.isDue(lastCheck: eightDays, now: now))
        XCTAssertTrue(UpdateSchedule.monthly.isDue(lastCheck: now.addingTimeInterval(-31 * 86400), now: now))
        XCTAssertEqual(
            UpdateSchedule.weekly.nextCheck(after: sixDays, now: now),
            sixDays.addingTimeInterval(7 * 86400))
    }

    func testAClockThatWentBackwardsDoesNotSilenceTheSchedule() {
        XCTAssertTrue(UpdateSchedule.weekly.isDue(lastCheck: now.addingTimeInterval(86400), now: now))
    }

    func testTheDefaultIsOff() {
        XCTAssertEqual(
            UpdateSchedule(rawValue: ""),
            nil,
            "an unset preference falls back to .never in the app")
        XCTAssertEqual(UpdateSchedule.allCases.first, .never)
    }
}
