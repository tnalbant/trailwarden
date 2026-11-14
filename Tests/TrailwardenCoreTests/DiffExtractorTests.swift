// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class DiffExtractorTests: XCTestCase {
    func testUnifiedDiffIsParsed() throws {
        let text = """
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
         let a = 1
        -let b = 2
        +let b = 3
         let c = 4
        """

        let lines = try XCTUnwrap(DiffExtractor.diff(in: text))

        XCTAssertEqual(lines.filter { $0.kind == .addition }.map(\.text), ["let b = 3"])
        XCTAssertEqual(lines.filter { $0.kind == .removal }.map(\.text), ["let b = 2"])
        XCTAssertEqual(lines.filter { $0.kind == .context }.map(\.text), [" let a = 1", " let c = 4"])
        XCTAssertEqual(lines.filter { $0.kind == .header }.count, 3)
    }

    func testCodexPatchIsParsed() throws {
        let text = """
        *** Begin Patch
        *** Update File: scripts/release.sh
        -echo old
        +echo new
        *** End Patch
        """

        let lines = try XCTUnwrap(DiffExtractor.diff(in: text))

        XCTAssertEqual(lines.first, DiffLine(kind: .header, text: "*** Begin Patch"))
        XCTAssertEqual(lines.first { $0.kind == .addition }?.text, "echo new")
        XCTAssertEqual(lines.first { $0.kind == .removal }?.text, "echo old")
    }

    func testCodexJSWrappedPatchIsUnescaped() throws {
        // The shape this machine's transcripts actually use: the patch lives in a
        // JavaScript string, so every newline and quote is escaped.
        let text = #"const patch = "*** Begin Patch\n*** Add File: tools/run.py\n+print(\"hi\")\n-old line\n*** End Patch";\ntext(await tools.apply_patch(patch));"#

        let lines = try XCTUnwrap(DiffExtractor.diff(in: text))

        XCTAssertEqual(lines.first?.kind, .header)
        XCTAssertEqual(lines.first?.text, "*** Begin Patch")
        XCTAssertEqual(lines.filter { $0.kind == .addition }.map(\.text), [#"print("hi")"#])
        XCTAssertEqual(lines.filter { $0.kind == .removal }.map(\.text), ["old line"])
        XCTAssertFalse(lines.contains { $0.text.contains("apply_patch") }, "the JS wrapper is not part of the diff")
        XCTAssertFalse(lines.contains { $0.text.contains("const patch") })
    }

    func testCodexPatchWithoutEndMarker() throws {
        let text = "*** Begin Patch\n*** Update File: a.txt\n-one\n+one!"

        let lines = try XCTUnwrap(DiffExtractor.diff(in: text))
        XCTAssertEqual(lines.filter { $0.kind == .addition }.map(\.text), ["one!"])
    }

    func testThreeChangedLinesWithoutMarkerStillCount() throws {
        let text = """
        -one
        -two
        -three
        +four
        """

        let lines = try XCTUnwrap(DiffExtractor.diff(in: text))
        XCTAssertEqual(lines.filter { $0.kind == .removal }.count, 3)
    }

    func testShellCommandIsNotADiff() {
        XCTAssertNil(DiffExtractor.diff(in: "rm -rf ./build && ls -la"))
        XCTAssertNil(DiffExtractor.diff(in: "git log --oneline -n 5"))
        XCTAssertNil(DiffExtractor.diff(in: "echo -n done"))
    }

    func testShortSingleDashIsNotADiff() {
        XCTAssertNil(DiffExtractor.diff(in: "-x\nplain text\nanother line"))
    }

    func testEmptyText() {
        XCTAssertNil(DiffExtractor.diff(in: ""))
    }
}
