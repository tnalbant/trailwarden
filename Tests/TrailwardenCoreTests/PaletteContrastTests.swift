// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class PaletteContrastTests: XCTestCase {
    private var modes: [(name: String, colours: [PaletteRole: RGBA])] {
        [("light", PaletteSpec.paper.light), ("dark", PaletteSpec.paper.dark)]
    }

    func testTextRolesMeetAA() throws {
        for mode in modes {
            for background in [PaletteRole.paper, .surface] {
                let ground = try XCTUnwrap(mode.colours[background])
                for role in PaletteRole.textRoles {
                    let colour = try XCTUnwrap(mode.colours[role])
                    let ratio = PaletteSpec.contrast(colour, on: ground)
                    XCTAssertGreaterThanOrEqual(
                        ratio, 4.5, "\(role) on \(background) in \(mode.name) is \(ratio)")
                }
            }
        }
    }

    func testTextOnAccentTextFillMeetsAA() throws {
        for mode in modes {
            let fill = try XCTUnwrap(mode.colours[.accentText])
            let text = try XCTUnwrap(mode.colours[.paper])
            let ratio = PaletteSpec.contrast(text, on: fill)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "paper on accentText in \(mode.name) is \(ratio)")
        }
    }

    func testContrastFormula() {
        let black = RGBA(red: 0, green: 0, blue: 0)
        let white = RGBA(red: 1, green: 1, blue: 1)
        XCTAssertEqual(PaletteSpec.contrast(black, on: white), 21.0, accuracy: 0.01)
        XCTAssertEqual(
            PaletteSpec.contrast(RGBA(hex: 0xE4572E), on: RGBA(hex: 0xFAF7F2)), 3.45, accuracy: 0.02)
    }
}
