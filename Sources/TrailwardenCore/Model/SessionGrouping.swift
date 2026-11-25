// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// How long ago a session last wrote, in the buckets the sidebar shows.
public enum SessionAge: CaseIterable, Sendable {
    case today, yesterday, thisWeek, older
}

/// Sorts sessions into calendar-day buckets, newest first.
public enum SessionGrouping {
    /// Groups by `endedAt ?? startedAt`. "This week" is the rest of the calendar's
    /// current week, so it excludes today and yesterday. Empty groups are dropped.
    public static func group(
        _ sessions: [SessionSummary],
        now: Date,
        calendar: Calendar) -> [(SessionAge, [SessionSummary])]
    {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.dateInterval(of: .weekOfYear, for: now)

        func age(of session: SessionSummary) -> SessionAge {
            let day = calendar.startOfDay(for: session.endedAt)
            if day >= today {
                return .today
            }
            if day >= yesterday {
                return .yesterday
            }
            if let week, day >= week.start {
                return .thisWeek
            }
            return .older
        }

        let sorted = sessions.sorted { $0.endedAt > $1.endedAt }
        let buckets = Dictionary(grouping: sorted, by: age(of:))
        return SessionAge.allCases.compactMap { age in
            guard let items = buckets[age], !items.isEmpty else { return nil }
            return (age, items)
        }
    }
}
