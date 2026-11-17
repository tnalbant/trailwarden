// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// How often the app may look for a new version on its own.
///
/// `never` is the default: out of the box Trailwarden only goes online when the
/// reader clicks "Check for updates". A reader who picks a schedule allows the
/// same single GET — one small JSON file, no identifiers — at most this often.
/// The decision lives here, without network code, so it can be tested and read.
public enum UpdateSchedule: String, CaseIterable, Sendable, Identifiable {
    case never
    case weekly
    case monthly

    public static let storageKey = "trailwarden.updates.schedule"
    public static let lastCheckKey = "trailwarden.updates.lastCheck"
    public static let notifiedVersionKey = "trailwarden.updates.notifiedVersion"

    public var id: String {
        rawValue
    }

    public var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .weekly: 7 * 86400
        case .monthly: 30 * 86400
        }
    }

    /// Whether a check is due. A schedule that has never run is due at once; a
    /// clock that moved backwards (last check "in the future") is treated as
    /// due too, rather than silencing the schedule until that date.
    public func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let interval else { return false }
        guard let lastCheck else { return true }
        if lastCheck > now {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// The moment the next check becomes due, for the Settings line.
    public func nextCheck(after lastCheck: Date?, now: Date = Date()) -> Date? {
        guard let interval else { return nil }
        guard let lastCheck, lastCheck <= now else { return now }
        return lastCheck.addingTimeInterval(interval)
    }
}
