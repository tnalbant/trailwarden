// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// The interface string in the language the user picked. Views that render text
/// also declare `@AppStorage("trailwarden.language")` so a change redraws them.
@inline(__always)
func L(_ key: UIString) -> String {
    LocalizationStore.current.text(key)
}

/// A formatted interface string, e.g. `Lf(.eventCount, [12])`.
@inline(__always)
func Lf(_ key: UIString, _ arguments: [CVarArg]) -> String {
    String(format: LocalizationStore.current.text(key), arguments: arguments)
}
