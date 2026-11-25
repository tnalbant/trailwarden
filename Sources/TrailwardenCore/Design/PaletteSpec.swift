// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// An sRGB colour with components in 0...1.
public struct RGBA: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB` with an optional alpha.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha)
    }
}

/// The named colours of the palette. Text roles are the ones that must stay
/// readable (4.5:1) on both `paper` and `surface`.
public enum PaletteRole: String, CaseIterable, Sendable {
    case paper, surface, ink, secondary, tertiary, accent, accentText, hairline, selection
    case severityCritical, severityWarn, severityInfo
    case diffAddition, diffRemoval, diffHeader

    public static let textRoles: [PaletteRole] = [
        .ink, .secondary, .tertiary, .accentText,
        .severityCritical, .severityWarn, .severityInfo,
        .diffAddition, .diffRemoval, .diffHeader
    ]
}

/// The palette as data, so its contrast can be tested without AppKit.
public struct PaletteSpec: Sendable {
    public let light: [PaletteRole: RGBA]
    public let dark: [PaletteRole: RGBA]

    public static let paper = PaletteSpec(
        light: [
            .paper: RGBA(hex: 0xFAF7F2),
            .surface: RGBA(hex: 0xF2ECE3),
            .ink: RGBA(hex: 0x191714),
            .secondary: RGBA(hex: 0x191714, alpha: 0.66),
            .tertiary: RGBA(hex: 0x191714, alpha: 0.64),
            .accent: RGBA(hex: 0xE4572E),
            .accentText: RGBA(hex: 0xB8431F),
            .hairline: RGBA(hex: 0x191714, alpha: 0.14),
            .selection: RGBA(hex: 0xE4572E, alpha: 0.13),
            .severityCritical: RGBA(hex: 0xB3271B),
            .severityWarn: RGBA(hex: 0x8A5A00),
            .severityInfo: RGBA(hex: 0x2E4B7A),
            .diffAddition: RGBA(hex: 0x1B5E33),
            .diffRemoval: RGBA(hex: 0x992C1B),
            .diffHeader: RGBA(hex: 0x5A544A)
        ],
        dark: [
            .paper: RGBA(hex: 0x1B1A18),
            .surface: RGBA(hex: 0x242321),
            .ink: RGBA(hex: 0xF3F0EA),
            .secondary: RGBA(hex: 0xF3F0EA, alpha: 0.62),
            .tertiary: RGBA(hex: 0xF3F0EA, alpha: 0.55),
            .accent: RGBA(hex: 0xFF7A50),
            .accentText: RGBA(hex: 0xFF7A50),
            .hairline: RGBA(hex: 0xFFFFFF, alpha: 0.13),
            .selection: RGBA(hex: 0xFF7A50, alpha: 0.20),
            .severityCritical: RGBA(hex: 0xFF8B7A),
            .severityWarn: RGBA(hex: 0xF5C260),
            .severityInfo: RGBA(hex: 0x8FB8F5),
            .diffAddition: RGBA(hex: 0x86DCA5),
            .diffRemoval: RGBA(hex: 0xFF9A86),
            .diffHeader: RGBA(hex: 0xB2AB9D)
        ])

    /// WCAG 2.x contrast ratio. A translucent foreground is composited over
    /// the background first; the background is treated as opaque.
    public static func contrast(_ foreground: RGBA, on background: RGBA) -> Double {
        let alpha = foreground.alpha
        let blended = RGBA(
            red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha))
        let first = luminance(blended)
        let second = luminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ colour: RGBA) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.red) + 0.7152 * linear(colour.green) + 0.0722 * linear(colour.blue)
    }
}
