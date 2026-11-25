// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class TimelineQueryTests: XCTestCase {
    private var store: EventStore!

    override func setUpWithError() throws {
        store = try EventStore(inMemory: true)
    }

    private func event(
        id: String,
        seconds: TimeInterval,
        cwd: String = "/Users/demo/dev/alpha",
        session: String = "s-alpha",
        agent: Agent = .claudeCode,
        preview: String = "hello",
        severity: Severity? = nil) -> Event
    {
        Event(
            id: id,
            ts: Date(timeIntervalSince1970: seconds),
            agent: agent,
            sessionId: session,
            kind: .toolCall,
            cwd: cwd,
            tool: "Bash",
            command: "cmd \(id)",
            paths: [],
            preview: preview,
            risk: severity.map { [RiskHit(ruleId: "R1", severity: $0, message: "m")] } ?? [],
            rawJSON: nil)
    }

    private func seed() throws {
        try store.insert(events: [
            event(id: "e1", seconds: 1000, preview: "alpha release notes", severity: .critical),
            event(id: "e2", seconds: 2000, preview: "beta release notes"),
            event(
                id: "e3",
                seconds: 3000,
                cwd: "/Users/demo/dev/beta",
                session: "s-beta",
                agent: .codex,
                preview: "gamma deployment"),
            event(id: "e4", seconds: 4000, preview: "delta release", severity: .warn),
            event(
                id: "e5",
                seconds: 5000,
                cwd: "/Users/demo/dev/beta",
                session: "s-beta",
                agent: .codex,
                preview: "epsilon notes")
        ])
    }

    func testUntilFilter() throws {
        try seed()
        let events = try store.events(matching: EventQuery(until: Date(timeIntervalSince1970: 2500)))
        XCTAssertEqual(events.map(\.id), ["e2", "e1"])
    }

    func testPaginationDoesNotOverlap() throws {
        try seed()
        let first = try store.events(matching: EventQuery(limit: 2))
        let second = try store.events(matching: EventQuery(limit: 2, offset: 2))

        XCTAssertEqual(first.map(\.id), ["e5", "e4"])
        XCTAssertEqual(second.map(\.id), ["e3", "e2"])
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
    }

    func testOffsetIsIgnoredWithoutLimit() throws {
        try seed()
        let events = try store.events(matching: EventQuery(offset: 3))
        XCTAssertEqual(events.count, 5, "an offset alone must not silently truncate the result")
    }

    func testProjectFilter() throws {
        try seed()
        let events = try store.events(matching: EventQuery(projects: ["/Users/demo/dev/beta"]))
        XCTAssertEqual(events.map(\.id), ["e5", "e3"])
    }

    func testSessionFilter() throws {
        try seed()
        let events = try store.events(matching: EventQuery(sessionIDs: ["s-alpha"]))
        XCTAssertEqual(events.map(\.id), ["e4", "e2", "e1"])
    }

    func testSearchMatchesPreviewText() throws {
        try seed()
        let events = try store.events(matching: EventQuery(search: "release"))
        XCTAssertEqual(events.map(\.id), ["e4", "e2", "e1"])
    }

    func testSearchIsAPhraseAndCannotInjectFTSSyntax() throws {
        try seed()

        let hyphenated = try store.events(matching: EventQuery(search: "release notes"))
        XCTAssertEqual(hyphenated.map(\.id), ["e2", "e1"], "the two words form one phrase")

        let hostile = try store.events(matching: EventQuery(search: "note* OR preview:gamma"))
        XCTAssertTrue(hostile.isEmpty, "quoted input is a phrase, not an FTS expression")
    }

    func testSearchMatchesTheStartOfAWord() throws {
        try seed()

        // Typing the beginning of a token has to find it: the whole point of a
        // search box is that you need not remember the exact word.
        let events = try store.events(matching: EventQuery(search: "rele"))
        XCTAssertEqual(events.map(\.id), ["e4", "e2", "e1"])
    }

    func testEveryWordHasToAppearButOrderDoesNotMatter() throws {
        try seed()

        let events = try store.events(matching: EventQuery(search: "notes release"))
        XCTAssertEqual(events.map(\.id), ["e2", "e1"], "both words, any order")
    }

    func testSearchOfPunctuationAloneFiltersNothing() throws {
        try seed()

        // A dash has no tokens; it must not become a syntax error, and it must not
        // silently empty the list either.
        let events = try store.events(matching: EventQuery(search: " - "))
        XCTAssertEqual(events.count, 5)
    }

    func testSearchCombinesWithFilters() throws {
        try seed()
        let events = try store.events(matching: EventQuery(minimumSeverity: .warn, search: "release"))
        XCTAssertEqual(events.map(\.id), ["e4", "e1"], "only events that are also findings")
    }

    func testCountMatchesTheListedEvents() throws {
        try seed()

        let queries = [
            EventQuery(),
            EventQuery(limit: 2),
            EventQuery(limit: 2, offset: 2),
            EventQuery(minimumSeverity: .warn),
            EventQuery(search: "release"),
            EventQuery(agents: [.codex], search: "notes"),
            EventQuery(since: Date(timeIntervalSince1970: 2500), limit: 1)
        ]

        for query in queries {
            // The count is the size of the whole result set, not of one page.
            var unlimited = query
            unlimited.limit = nil
            unlimited.offset = nil
            XCTAssertEqual(
                try store.eventCount(matching: query),
                try store.events(matching: unlimited).count,
                "count and list disagree for \(query)")
        }
        XCTAssertEqual(try store.eventCount(matching: EventQuery()), 5)
    }

    func testExcludedKindsAreLeftOut() throws {
        try store.insert(events: [
            event(id: "tool", seconds: 1000, preview: "ran a tool"),
            Event(
                id: "tokens",
                ts: Date(timeIntervalSince1970: 1001),
                agent: .codex,
                sessionId: "s-alpha",
                kind: .tokenUsage,
                preview: "tokens: 66358 in",
                risk: [],
                rawJSON: nil),
            Event(
                id: "start",
                ts: Date(timeIntervalSince1970: 1002),
                agent: .codex,
                sessionId: "s-alpha",
                kind: .sessionStart,
                preview: "session started",
                risk: [],
                rawJSON: nil)
        ])

        let all = try store.events(matching: EventQuery())
        XCTAssertEqual(all.count, 3)

        let quiet = try store.events(matching: EventQuery(excludedKinds: [.tokenUsage, .sessionStart]))
        XCTAssertEqual(quiet.map(\.id), ["tool"])
        XCTAssertEqual(try store.eventCount(matching: EventQuery(excludedKinds: [.tokenUsage])), 2)
    }

    func testProjectsGroupByWorkingDirectory() throws {
        try seed()
        let projects = try store.projects()

        XCTAssertEqual(projects.map(\.cwd), ["/Users/demo/dev/beta", "/Users/demo/dev/alpha"])
        let beta = try XCTUnwrap(projects.first)
        XCTAssertEqual(beta.sessionCount, 1)
        XCTAssertEqual(beta.eventCount, 2)
        XCTAssertEqual(beta.lastActivity, Date(timeIntervalSince1970: 5000))
    }
}
