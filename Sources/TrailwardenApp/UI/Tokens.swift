// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// Design tokens.
///
/// Apple's system palette does the heavy lifting: every colour here is either a
/// semantic AppKit colour (so light/dark/contrast modes follow the system) or a
/// dynamic pair tuned for the warm "paper" identity. Typography uses the system
/// faces — SF Pro for text, New York for the serif voice, SF Mono for code — so
/// it renders correctly on every Mac and in both appearances.
enum Tokens {
    enum Palette {
        static let paper = dynamic(
            light: NSColor(srgbRed: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255, alpha: 1),
            dark: NSColor(srgbRed: 0x1B / 255, green: 0x1A / 255, blue: 0x18 / 255, alpha: 1))
        static let surface = dynamic(
            light: NSColor(srgbRed: 0xF2 / 255, green: 0xEC / 255, blue: 0xE3 / 255, alpha: 1),
            dark: NSColor(srgbRed: 0x24 / 255, green: 0x23 / 255, blue: 0x21 / 255, alpha: 1))
        static let ink = dynamic(
            light: NSColor(srgbRed: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 1),
            dark: NSColor(srgbRed: 0xF3 / 255, green: 0xF0 / 255, blue: 0xEA / 255, alpha: 1))
        static let secondary = dynamic(
            light: NSColor(srgbRed: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 0.66),
            dark: NSColor(srgbRed: 0xF3 / 255, green: 0xF0 / 255, blue: 0xEA / 255, alpha: 0.62))
        static let tertiary = dynamic(
            light: NSColor(srgbRed: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 0.42),
            dark: NSColor(srgbRed: 0xF3 / 255, green: 0xF0 / 255, blue: 0xEA / 255, alpha: 0.40))
        static let accent = dynamic(
            light: NSColor(srgbRed: 0xE4 / 255, green: 0x57 / 255, blue: 0x2E / 255, alpha: 1),
            dark: NSColor(srgbRed: 0xFF / 255, green: 0x7A / 255, blue: 0x50 / 255, alpha: 1))
        static let hairline = dynamic(
            light: NSColor(srgbRed: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 0.14),
            dark: NSColor(white: 1, alpha: 0.13))
        static let selection = dynamic(
            light: NSColor(srgbRed: 0xE4 / 255, green: 0x57 / 255, blue: 0x2E / 255, alpha: 0.13),
            dark: NSColor(srgbRed: 0xFF / 255, green: 0x7A / 255, blue: 0x50 / 255, alpha: 0.20))
        /// Diff colours keep at least 4.5:1 against the surface in both modes.
        static let diffAddition = dynamic(
            light: NSColor(srgbRed: 0x1B / 255, green: 0x5E / 255, blue: 0x33 / 255, alpha: 1),
            dark: NSColor(srgbRed: 0x86 / 255, green: 0xDC / 255, blue: 0xA5 / 255, alpha: 1))
        static let diffRemoval = dynamic(
            light: NSColor(srgbRed: 0x99 / 255, green: 0x2C / 255, blue: 0x1B / 255, alpha: 1),
            dark: NSColor(srgbRed: 0xFF / 255, green: 0x9A / 255, blue: 0x86 / 255, alpha: 1))
        static let diffHeader = dynamic(
            light: NSColor(srgbRed: 0x5A / 255, green: 0x54 / 255, blue: 0x4A / 255, alpha: 1),
            dark: NSColor(srgbRed: 0xB2 / 255, green: 0xAB / 255, blue: 0x9D / 255, alpha: 1))

        static func severity(_ severity: Severity) -> Color {
            switch severity {
            case .critical: dynamic(
                    light: NSColor(srgbRed: 0xB3 / 255, green: 0x27 / 255, blue: 0x1B / 255, alpha: 1),
                    dark: NSColor(srgbRed: 0xFF / 255, green: 0x8B / 255, blue: 0x7A / 255, alpha: 1))
            case .warn: dynamic(
                    light: NSColor(srgbRed: 0x8A / 255, green: 0x5A / 255, blue: 0x00 / 255, alpha: 1),
                    dark: NSColor(srgbRed: 0xF5 / 255, green: 0xC2 / 255, blue: 0x60 / 255, alpha: 1))
            case .info: dynamic(
                    light: NSColor(srgbRed: 0x2E / 255, green: 0x4B / 255, blue: 0x7A / 255, alpha: 1),
                    dark: NSColor(srgbRed: 0x8F / 255, green: 0xB8 / 255, blue: 0xF5 / 255, alpha: 1))
            }
        }

        static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }
    }

    enum Typography {
        /// New York, the system serif: headings keep the paper voice and still
        /// inherit Dynamic Type and every script the system supports.
        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// An 8 pt grid, so every gap in the app is one of these.
    enum Metrics {
        static let panelWidth: CGFloat = 340
        static let gutter: CGFloat = 14
        static let gap: CGFloat = 8
        static let radius: CGFloat = 10
        static let hairline: CGFloat = 1
    }
}

/// A one pixel rule in the ink colour, the only separator the panel uses.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.Palette.hairline)
            .frame(height: Tokens.Metrics.hairline)
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    init(text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text.uppercased())
                .font(Tokens.Typography.text(10, weight: .semibold))
                .kerning(0.7)
                .foregroundStyle(Tokens.Palette.secondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Tokens.Typography.mono(9))
                    .foregroundStyle(Tokens.Palette.tertiary)
            }
        }
    }
}
