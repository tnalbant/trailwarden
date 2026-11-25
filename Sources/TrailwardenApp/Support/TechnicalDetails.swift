// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// One setting for everything a reader does not need by default: raw tool names,
/// rule ids, session ids, raw records and the system's own error text. Views
/// read it with `@AppStorage(TechnicalDetails.storageKey)`; code that builds a
/// string reads `isOn`.
enum TechnicalDetails {
    static let storageKey = "trailwarden.technicalDetails"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    /// The sentence a reader sees when something failed; the raw text follows it
    /// only with technical details on.
    static func errorText(_ error: Error) -> String {
        errorText(raw: String(describing: error))
    }

    static func errorText(raw: String) -> String {
        errorText(raw: raw, technical: isOn)
    }

    static func errorText(raw: String, technical: Bool) -> String {
        let plain = L(.genericError)
        return technical ? "\(plain)\n\(raw)" : plain
    }

    /// The severity badge: the rule's title, with its id after it in technical mode.
    static func badge(title: String, ruleId: String, technical: Bool) -> String {
        technical ? "\(title) · \(ruleId)" : title
    }
}
