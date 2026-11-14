// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI

/// "Paper & ink" tokens from the product spec: warm paper, near-black ink, one
/// accent, serif headings and monospaced code. Thin rules instead of shadows.
enum Tokens {
    enum Palette {
        static let paper = Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255)
        static let ink = Color(red: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255)
        static let accent = Color(red: 0xE4 / 255, green: 0x57 / 255, blue: 0x2E / 255)
        static let surface = Color(red: 0xF2 / 255, green: 0xEC / 255, blue: 0xE3 / 255)
        static let hairline = Color(red: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255).opacity(0.14)
        // Diff colours: dark enough to stay above 4.5:1 on paper.
        static let diffAddition = Color(red: 0x1B / 255, green: 0x5E / 255, blue: 0x33 / 255)
        static let diffRemoval = Color(red: 0x99 / 255, green: 0x2C / 255, blue: 0x1B / 255)
        static let diffHeader = Color(red: 0x5A / 255, green: 0x54 / 255, blue: 0x4A / 255)
        static let secondary = Color(red: 0x19 / 255, green: 0x17 / 255, blue: 0x14 / 255).opacity(0.66)
    }

    enum Typography {
        static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom("Georgia", size: size).weight(weight)
        }

        static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    enum Metrics {
        static let panelWidth: CGFloat = 320
        static let gutter: CGFloat = 14
        static let radius: CGFloat = 9
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

    var body: some View {
        Text(text.uppercased())
            .font(Tokens.Typography.text(10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Tokens.Palette.secondary)
    }
}
