// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// How long Trailwarden keeps its own record. Forever is the default; the 0.2.5
/// `trailwarden.retentionDays` value is deliberately ignored.
public enum RetentionChoice: String, CaseIterable, Sendable {
    case forever, oneYear, ninetyDays

    public static let storageKey = "trailwarden.retention"

    /// nil means nothing is ever pruned.
    public var days: Int? {
        switch self {
        case .forever: nil
        case .oneYear: 365
        case .ninetyDays: 90
        }
    }

    public static func resolve(stored: String?) -> RetentionChoice {
        stored.flatMap(RetentionChoice.init(rawValue:)) ?? .forever
    }
}
