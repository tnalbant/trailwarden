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
