// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

extension Int {
    /// `Int(_: Double)` traps on NaN, infinity and anything past ±9.2e18. Token
    /// counts and ids come from other programs' databases and JSON, so one odd
    /// value would end the whole scan; this clamps instead (NaN becomes 0).
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= Double(Int.max) {
            self = .max
        } else if value <= Double(Int.min) {
            self = .min
        } else {
            self = Int(value)
        }
    }
}

public extension Int {
    /// `self + other`, clamped to `Int.max` / `Int.min` instead of trapping.
    /// Token counts come from other programs' data; one absurd row must not
    /// crash the app when it is added to a total.
    func saturatingAdd(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        guard overflow else { return sum }
        return other > 0 ? .max : .min
    }
}
