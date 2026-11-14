// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class ResumeCommandTests: XCTestCase {
    func testEachAgentGetsItsOwnSpelling() {
        XCTAssertEqual(
            ResumeCommand.command(agent: .claudeCode, sessionId: "abc", cwd: nil),
            "claude --resume abc"
        )
        XCTAssertEqual(
            ResumeCommand.command(agent: .codex, sessionId: "abc", cwd: nil),
            "codex resume abc"
        )
        XCTAssertEqual(
            ResumeCommand.command(agent: .gemini, sessionId: "abc", cwd: nil),
            "gemini --resume abc"
        )
        XCTAssertEqual(
            ResumeCommand.command(agent: .opencode, sessionId: "abc", cwd: nil),
            "opencode --session abc"
        )
    }

    func testDirectoryIsQuoted() {
        XCTAssertEqual(
            ResumeCommand.command(agent: .codex, sessionId: "abc", cwd: "/Users/demo/my project"),
            "cd '/Users/demo/my project' && codex resume abc"
        )
        XCTAssertEqual(ResumeCommand.quoted("/tmp/it's here"), #"'/tmp/it'\''s here'"#)
    }

    func testEmptySessionIsNotACcommand() {
        XCTAssertNil(ResumeCommand.command(agent: .codex, sessionId: "", cwd: nil))
    }
}
