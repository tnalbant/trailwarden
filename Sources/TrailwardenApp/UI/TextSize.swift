// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import SwiftUI
import TrailwardenCore

/// How large the interface text is. Stored as a string so the choice survives
/// restarts and can be changed from Settings or `defaults write`.
enum TextSize: String, CaseIterable, Identifiable {
    case standard
    case large
    case larger

    static let storageKey = "trailwarden.textSize"

    /// Read at draw time; views refresh through `@AppStorage(TextSize.storageKey)`.
    static var current: TextSize {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? TextSize.standard.rawValue
        return TextSize(rawValue: raw) ?? .standard
    }

    var id: String {
        rawValue
    }

    var factor: CGFloat {
        switch self {
        case .standard: 1.0
        case .large: 1.15
        case .larger: 1.3
        }
    }

    var label: String {
        let localizer = LocalizationStore.current
        switch self {
        case .standard: return localizer.text(.textSizeStandard)
        case .large: return localizer.text(.textSizeLarge)
        case .larger: return localizer.text(.textSizeLarger)
        }
    }
}

/// The named roles every piece of text in the app is set in.
enum TextStyle {
    case display
    case title
    case subtitle
    case heading
    case body
    case callout
    case caption
    case label
    case code
    case codeSmall

    /// Point size at the standard text size.
    var baseSize: CGFloat {
        switch self {
        case .display: 24
        case .title: 18
        case .subtitle: 14
        case .heading: 13
        case .body: 12
        case .callout: 11
        case .caption: 10.5
        case .label: 10
        case .code: 11.5
        case .codeSmall: 10.5
        }
    }

    var weight: Font.Weight {
        switch self {
        case .heading, .label: .semibold
        default: .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .display, .title, .subtitle: .serif
        case .code, .codeSmall: .monospaced
        default: .default
        }
    }
}
