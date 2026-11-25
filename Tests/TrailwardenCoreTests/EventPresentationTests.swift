// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class EventPresentationTests: XCTestCase {
    private func makeEvent(
        kind: EventKind = .toolCall,
        tool: String? = nil,
        command: String? = nil,
        paths: [String] = [],
        preview: String? = nil) -> Event
    {
        Event(
            id: "event-\(UUID().uuidString)",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .claudeCode,
            sessionId: "session-1",
            kind: kind,
            tool: tool,
            command: command,
            paths: paths,
            preview: preview)
    }

    func testVerbs() {
        XCTAssertEqual(EventPresentation.verb(for: makeEvent(kind: .message)), .said)
        XCTAssertEqual(EventPresentation.verb(for: makeEvent(kind: .reasoning)), .thought)
        let table: [(String, ActionVerb)] = [
            ("run_shell_command", .ran), ("Bash", .ran), ("exec_command", .ran),
            ("glob", .searched), ("grep_search", .searched), ("list_directory", .searched),
            ("Grep", .searched), ("Glob", .searched), ("LS", .searched),
            ("glob_file_search", .searched), ("list_dir", .searched), ("ripgrep", .searched),
            ("codebase_search", .searched), ("rg", .searched), ("websearch", .searched),
            ("read_file", .read), ("Read", .read),
            ("write_file", .wrote), ("Write", .wrote), ("create_file", .wrote),
            ("replace", .edited), ("Edit", .edited), ("MultiEdit", .edited), ("apply_patch", .edited),
            ("str_replace_editor", .edited),
            ("mystery_tool", .other)
        ]
        for (tool, expected) in table {
            XCTAssertEqual(EventPresentation.verb(for: makeEvent(tool: tool)), expected, tool)
        }
        XCTAssertEqual(EventPresentation.verb(for: makeEvent(kind: .toolCall)), .other)
    }

    func testDisplayPath() {
        let home = "/Users/demo"
        let inside = EventPresentation.displayPath(
            "/Users/demo/app/src/a.ts",
            cwd: "/Users/demo/app",
            home: home)
        XCTAssertEqual(inside, DisplayPath(text: "src/a.ts", outsideProject: false))
        let slash = EventPresentation.displayPath(
            "/Users/demo/app/src/a.ts",
            cwd: "/Users/demo/app/",
            home: home)
        XCTAssertEqual(slash, inside)
        let same = EventPresentation.displayPath("/Users/demo/app", cwd: "/Users/demo/app", home: home)
        XCTAssertEqual(same, DisplayPath(text: ".", outsideProject: false))
        let outside = EventPresentation.displayPath("/Users/demo/.zshrc", cwd: "/Users/demo/app", home: home)
        XCTAssertEqual(outside, DisplayPath(text: "~/.zshrc", outsideProject: true))
        let noCwd = EventPresentation.displayPath("/Users/demo/.zshrc", cwd: nil, home: home)
        XCTAssertEqual(noCwd, DisplayPath(text: "~/.zshrc", outsideProject: false))
        let tmp = EventPresentation.displayPath("/private/tmp/x", cwd: "/tmp", home: home)
        XCTAssertEqual(tmp, DisplayPath(text: "x", outsideProject: false))
        let sibling = EventPresentation.displayPath(
            "/Users/demo/app2/a.ts",
            cwd: "/Users/demo/app",
            home: home)
        XCTAssertEqual(sibling, DisplayPath(text: "~/app2/a.ts", outsideProject: true))
    }

    func testSummary() {
        let english = Localizer(language: .english)
        let ran = makeEvent(tool: "Bash", command: "npm  test\n--silent")
        XCTAssertEqual(EventPresentation.summary(for: ran, localizer: english), "Ran npm test --silent")
        var edit = makeEvent(tool: "Edit", paths: ["/Users/demo/app/src/retry.ts"])
        edit = edit.withCwd("/Users/demo/app")
        XCTAssertEqual(EventPresentation.summary(for: edit, localizer: english), "Edited src/retry.ts")
        let said = makeEvent(kind: .message, preview: "All done.")
        XCTAssertEqual(EventPresentation.summary(for: said, localizer: english), "All done.")
    }

    func testSummaryFallsBackToPreview() {
        let english = Localizer(language: .english)
        let execute = makeEvent(tool: "execute", preview: "print(1 + 1)")
        XCTAssertEqual(EventPresentation.verb(for: execute), .ran)
        XCTAssertEqual(EventPresentation.summary(for: execute, localizer: english), "Ran print(1 + 1)")
        let grep = makeEvent(tool: "grep", preview: "grep TODO")
        XCTAssertEqual(EventPresentation.summary(for: grep, localizer: english), "Searched grep TODO")
        let fetch = makeEvent(tool: "webfetch", preview: "https://example.com/a")
        XCTAssertEqual(
            EventPresentation.summary(for: fetch, localizer: english),
            "Other https://example.com/a")
    }

    func testRuleTitleFallsBackToId() {
        let english = Localizer(language: .english)
        let hit = RiskHit(ruleId: "NOPE-1", severity: .warn, message: "m")
        XCTAssertEqual(EventPresentation.ruleTitle(hit, localizer: english), "NOPE-1")
        let known = RiskHit(ruleId: "R1", severity: .warn, message: "m")
        XCTAssertNotEqual(EventPresentation.ruleTitle(known, localizer: english), "R1")
    }

    func testEveryVerbIsTranslated() {
        for language in AppLanguage.translated {
            let localizer = Localizer(language: language)
            for verb in ActionVerb.allCases {
                let label = verb.label(localizer)
                XCTAssertFalse(label.isEmpty, "\(language.rawValue)/\(verb.rawValue)")
                XCTAssertNotEqual(label, verb.rawValue, "\(language.rawValue)/\(verb.rawValue)")
            }
        }
    }
}
