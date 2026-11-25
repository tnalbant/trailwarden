// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class ReportGoldenTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-11-14T09:00:00Z")!
    private let end = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!

    private var session: SessionSummary {
        SessionSummary(
            id: "sess-0001",
            agent: .claudeCode,
            cwd: "/Users/demo/dev/demo",
            gitBranch: "main",
            startedAt: start,
            endedAt: start.addingTimeInterval(5),
            eventCount: 3,
            criticalCount: 1)
    }

    private var events: [Event] {
        [
            Event(
                id: "e1", ts: start.addingTimeInterval(1), agent: .claudeCode, sessionId: "sess-0001",
                kind: .toolCall, cwd: "/Users/demo/dev/demo", gitBranch: "main", tool: "Bash",
                command: "rm -rf ~", paths: [], preview: "rm -rf ~",
                risk: [RiskHit(ruleId: "R1", severity: .critical, message: "destructive")],
                rawJSON: "{}"),
            Event(
                id: "e2", ts: start.addingTimeInterval(2), agent: .claudeCode, sessionId: "sess-0001",
                kind: .message, cwd: "/Users/demo/dev/demo", gitBranch: "main", tool: nil,
                command: nil, paths: [], preview: "hello", risk: [], rawJSON: "{}"),
            Event(
                id: "e3", ts: start.addingTimeInterval(3), agent: .claudeCode, sessionId: "sess-0001",
                kind: .toolCall, cwd: "/Users/demo/dev/demo", gitBranch: "main", tool: "Bash",
                command: "sudo ls", paths: [], preview: "sudo ls",
                risk: [RiskHit(ruleId: "R3", severity: .warn, message: "elevated")],
                rawJSON: "{}")
        ]
    }

    private var selection: AuditSelection {
        AuditSelection(since: nil, until: end, agents: [.claudeCode], minimumSeverity: nil, generatedAt: end)
    }

    func testMarkdownGolden() {
        let markdown = MarkdownReport.render(sessions: [session], events: events, selection: selection)

        let expected = """
        # Trailwarden audit record

        | | |
        |---|---|
        | Generated | 2026-11-14T12:00:00Z |
        | Window | everything up to 2026-11-14T12:00:00Z |
        | Agents | claude-code |
        | Minimum severity | any finding |

        ## Summary

        | Metric | Value |
        |---|---|
        | Sessions | 1 |
        | Events | 3 |
        | Findings | 2 |
        | Critical | 1 |
        | Warn | 1 |
        | Info | 0 |

        ## Sessions

        | Session | Agent | Project | Started (UTC) | Events | Critical |
        |---|---|---|---|---|---|
        | sess-0001 | claude-code | ~/dev/demo | 2026-11-14T09:00:00Z | 3 | 1 |

        ## Findings

        | Time (UTC) | Agent | Tool | Rule | Severity | Detail |
        |---|---|---|---|---|---|
        | 2026-11-14T09:00:03Z | claude-code | Bash | R3 | warn | sudo ls |
        | 2026-11-14T09:00:01Z | claude-code | Bash | R1 | critical | rm -rf ~ |

        ## Risk summary

        | Rule | Severity | Hits |
        |---|---|---|
        | R1 | critical | 1 |
        | R3 | warn | 1 |

        """
        XCTAssertEqual(markdown, expected)
    }

    func testMarkdownWithNoFindings() {
        let quiet = Event(
            id: "q1", ts: start, agent: .codex, sessionId: "s2", kind: .message,
            preview: "hello", risk: [], rawJSON: nil)

        let markdown = MarkdownReport.render(sessions: [], events: [quiet], selection: selection)

        XCTAssertTrue(markdown.contains("No findings in this window."))
        XCTAssertTrue(markdown.contains("No rules matched."))
    }

    func testMarkdownEscapesTableSeparators() {
        let event = Event(
            id: "p1", ts: start, agent: .claudeCode, sessionId: "s1", kind: .toolCall,
            tool: "Bash", command: "echo a | b", paths: [], preview: "echo a | b",
            risk: [RiskHit(ruleId: "R3", severity: .warn, message: "m")], rawJSON: nil)

        let markdown = MarkdownReport.render(sessions: [], events: [event], selection: selection)

        XCTAssertTrue(markdown.contains("echo a \\| b"))
    }

    func testJSONGoldenShape() throws {
        let data = try JSONReport.data(sessions: [session], events: events, selection: selection)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schema"] as? Int, 1)
        XCTAssertEqual(object["generated_at"] as? String, "2026-11-14T12:00:00Z")
        XCTAssertNil(object["minimum_severity"])
        XCTAssertEqual(object["agents"] as? [String], ["claude-code"])

        let window = try XCTUnwrap(object["window"] as? [String: Any])
        XCTAssertEqual(window["until"] as? String, "2026-11-14T12:00:00Z")
        XCTAssertNil(window["since"])

        let summary = try XCTUnwrap(object["summary"] as? [String: Any])
        XCTAssertEqual(summary["sessions"] as? Int, 1)
        XCTAssertEqual(summary["events"] as? Int, 3)
        XCTAssertEqual(summary["findings"] as? Int, 2)
        XCTAssertEqual(summary["critical"] as? Int, 1)

        let jsonEvents = try XCTUnwrap(object["events"] as? [[String: Any]])
        XCTAssertEqual(jsonEvents.count, 3)
        let newest = try XCTUnwrap(jsonEvents.first)
        XCTAssertEqual(newest["id"] as? String, "e3")
        XCTAssertEqual(newest["ts"] as? String, "2026-11-14T09:00:03Z")
        XCTAssertEqual(newest["cwd"] as? String, "~/dev/demo", "exports shorten the home directory")
        XCTAssertEqual(newest["session_id"] as? String, "sess-0001")
        let risk = try XCTUnwrap(newest["risk"] as? [[String: Any]])
        XCTAssertEqual(risk.first?["rule_id"] as? String, "R3")
        XCTAssertNil(newest["command_note"], "field names are snake_case, not camelCase")
        XCTAssertNil(newest["commandNote"])
    }

    func testJSONOmitsAbsentFields() throws {
        let data = try JSONReport.data(sessions: [], events: events, selection: selection)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let jsonEvents = try XCTUnwrap(object["events"] as? [[String: Any]])
        let message = try XCTUnwrap(jsonEvents.first { ($0["id"] as? String) == "e2" })

        XCTAssertNil(message["raw_json"], "the raw transcript line is a debug view, not export data")
        XCTAssertNil(message["command"], "a message event has no command key at all")
        XCTAssertNil(message["tool"])
        XCTAssertEqual(message["preview"] as? String, "hello")
    }

    func testSummaryCountsWorstSeverityPerEvent() {
        let events = [
            Event(
                id: "a",
                ts: start,
                agent: .claudeCode,
                sessionId: "s",
                kind: .toolCall,
                risk: [RiskHit(ruleId: "R1", severity: .critical, message: ""),
                       RiskHit(ruleId: "R3", severity: .warn, message: "")],
                rawJSON: nil)
        ]

        let summary = AuditReport.summarize(sessions: [], events: events)

        XCTAssertEqual(summary.findings, 1)
        XCTAssertEqual(summary.critical, 1)
        XCTAssertEqual(summary.warn, 0, "an event is counted once, at its worst severity")
    }

    func testSessionIDsStayDistinguishable() {
        let a = "01a1b2fb-1111-4a11-9c2e-aaaaaaaaaaaa"
        let b = "01a1b2fb-2222-4a11-9c2e-bbbbbbbbbbbb"

        XCTAssertNotEqual(MarkdownReport.shortID(a), MarkdownReport.shortID(b))
        XCTAssertEqual(MarkdownReport.shortID("sess-0001"), "sess-0001")
    }

    func testRuleCountsAreOrderedNumerically() {
        let events = [
            Event(
                id: "a",
                ts: start,
                agent: .claudeCode,
                sessionId: "s",
                kind: .toolCall,
                risk: [RiskHit(ruleId: "R10", severity: .warn, message: ""),
                       RiskHit(ruleId: "R2", severity: .critical, message: "")],
                rawJSON: nil),
            Event(
                id: "b",
                ts: start,
                agent: .claudeCode,
                sessionId: "s",
                kind: .toolCall,
                risk: [RiskHit(ruleId: "R2", severity: .critical, message: "")],
                rawJSON: nil)
        ]

        let counts = AuditReport.ruleCounts(events: events)

        XCTAssertEqual(counts.map(\.ruleId), ["R2", "R10"])
        XCTAssertEqual(counts.map(\.hits), [2, 1])
    }
}
