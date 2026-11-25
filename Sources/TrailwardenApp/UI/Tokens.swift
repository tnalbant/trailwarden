// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

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
        static let paper = color(.paper)
        static let surface = color(.surface)
        static let ink = color(.ink)
        static let secondary = color(.secondary)
        static let tertiary = color(.tertiary)
        /// Terracotta for marks only (dots, bars, strips, fills). Text uses `accentText`.
        static let accent = color(.accent)
        /// The terracotta that meets 4.5:1 as text on paper and surface.
        static let accentText = color(.accentText)
        static let hairline = color(.hairline)
        static let selection = color(.selection)
        static let diffAddition = color(.diffAddition)
        static let diffRemoval = color(.diffRemoval)
        static let diffHeader = color(.diffHeader)

        static func severity(_ severity: Severity) -> Color {
            switch severity {
            case .critical: color(.severityCritical)
            case .warn: color(.severityWarn)
            case .info: color(.severityInfo)
            }
        }

        /// One dynamic colour per role, read from the tested `PaletteSpec`.
        static func color(_ role: PaletteRole) -> Color {
            let spec = PaletteSpec.paper
            guard let light = spec.light[role], let dark = spec.dark[role] else { return .clear }
            return dynamic(light: nsColor(light), dark: nsColor(dark))
        }

        private static func nsColor(_ value: RGBA) -> NSColor {
            NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        }

        static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }
    }

    enum Typography {
        /// A named text role at the reader's chosen text size. Serif roles use New
        /// York, the system serif, so headings keep the paper voice; code uses SF Mono.
        static func font(_ style: TextStyle, weight: Font.Weight? = nil) -> Font {
            .system(
                size: style.baseSize * TextSize.current.factor,
                weight: weight ?? style.weight,
                design: style.design)
        }
    }

    /// An 8 pt grid, so every gap in the app is one of these.
    enum Metrics {
        static var panelWidth: CGFloat {
            switch TextSize.current {
            case .standard: 340
            case .large: 380
            case .larger: 420
            }
        }

        /// A fixed column width grown with the text size; a floor, never a clip.
        static func scaled(_ base: CGFloat) -> CGFloat {
            base * TextSize.current.factor
        }

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
                .font(Tokens.Typography.font(.label))
                .kerning(0.7)
                .foregroundStyle(Tokens.Palette.secondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.tertiary)
            }
        }
    }
}
