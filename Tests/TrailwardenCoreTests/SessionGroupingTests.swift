// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class SessionGroupingTests: XCTestCase {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func session(_ id: String, endedAt: String) -> SessionSummary {
        let end = date(endedAt)
        return SessionSummary(
            id: id, agent: .claudeCode, cwd: nil, gitBranch: nil,
            startedAt: end.addingTimeInterval(-60), endedAt: end,
            eventCount: 1, criticalCount: 0)
    }

    func testGroupsByCalendarDay() {
        // Friday 2026-11-27
        let now = date("2026-11-27T12:00:00Z")
        let sessions = [
            session("old", endedAt: "2026-10-20T10:00:00Z"),
            session("week", endedAt: "2026-11-24T10:00:00Z"),
            session("yesterday", endedAt: "2026-11-26T23:50:00Z"),
            session("today", endedAt: "2026-11-27T00:10:00Z")
        ]
        let groups = SessionGrouping.group(sessions, now: now, calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(groups.map(\.0), [.today, .yesterday, .thisWeek, .older])
        XCTAssertEqual(groups.map { $0.1.map(\.id) }, [["today"], ["yesterday"], ["week"], ["old"]])
    }

    func testDropsEmptyGroupsAndSortsNewestFirst() {
        let now = date("2026-11-27T12:00:00Z")
        let sessions = [
            session("a", endedAt: "2026-11-27T01:00:00Z"),
            session("b", endedAt: "2026-11-27T09:00:00Z")
        ]
        let groups = SessionGrouping.group(sessions, now: now, calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(groups.map(\.0), [.today])
        XCTAssertEqual(groups[0].1.map(\.id), ["b", "a"])
    }

    func testMondayWeekStart() {
        // Wednesday 2026-11-25; Sunday 2026-11-22 belongs to this week only when weeks start on Sunday.
        let now = date("2026-11-25T12:00:00Z")
        let sessions = [session("sunday", endedAt: "2026-11-22T12:00:00Z")]
        let sunday = SessionGrouping.group(sessions, now: now, calendar: calendar(firstWeekday: 1))
        let monday = SessionGrouping.group(sessions, now: now, calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(sunday.map(\.0), [.thisWeek])
        XCTAssertEqual(monday.map(\.0), [.older])
    }
}
