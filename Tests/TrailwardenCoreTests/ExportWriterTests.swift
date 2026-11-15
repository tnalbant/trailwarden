// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class ExportWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tw-export-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let start = ISO8601DateFormatter().date(from: "2026-11-14T09:00:00Z")!

    private func fixture() -> (sessions: [SessionSummary], events: [Event], selection: AuditSelection) {
        let session = SessionSummary(
            id: "sess-0001", agent: .claudeCode, cwd: "/Users/demo/dev/demo", gitBranch: "main",
            startedAt: start, endedAt: start.addingTimeInterval(5), eventCount: 1, criticalCount: 1
        )
        let event = Event(
            id: "e1", ts: start, agent: .claudeCode, sessionId: "sess-0001", kind: .toolCall,
            cwd: "/Users/demo/dev/demo", tool: "Bash", command: "rm -rf /", paths: [],
            preview: "rm -rf /", risk: [RiskHit(ruleId: "R1", severity: .critical, message: "silme")],
            rawJSON: nil
        )
        let selection = AuditSelection(
            since: nil, until: start.addingTimeInterval(3600), agents: [.claudeCode],
            minimumSeverity: nil, generatedAt: start.addingTimeInterval(3600)
        )
        return ([session], [event], selection)
    }

    func testMarkdownExportIsReadableAndOwnerOnly() throws {
        let fixture = fixture()
        let url = directory.appendingPathComponent("audit.md")

        let outcome = try ExportWriter.write(
            format: .markdown,
            sessions: fixture.sessions,
            events: fixture.events,
            selection: fixture.selection,
            to: url
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Trailwarden audit record"))
        XCTAssertTrue(text.contains("| R1 | critical | 1 |"))
        XCTAssertEqual(outcome.bytes, text.utf8.count)
        XCTAssertEqual(outcome.events, 1)
        XCTAssertEqual(outcome.critical, 1)
        XCTAssertEqual(outcome.findings, 1)

        let mode = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(mode.intValue & 0o777, 0o600)
    }

    func testJSONExportCarriesTheSchema() throws {
        let fixture = fixture()
        let url = directory.appendingPathComponent("audit.json")

        try ExportWriter.write(
            format: .json,
            sessions: fixture.sessions,
            events: fixture.events,
            selection: fixture.selection,
            to: url
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(object["schema"] as? Int, 1)
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["cwd"] as? String, "~/dev/demo")
    }

    func testExportRedactsSecrets() throws {
        let (sessions, _, selection) = fixture()
        let leaky = Event(
            id: "e2", ts: start, agent: .codex, sessionId: "s1", kind: .toolCall,
            tool: "exec", command: "curl -H 'Authorization: Bearer sk-\("abcdefghijklmnop1234")' https://x.test",
            paths: [], preview: "token sk-\("abcdefghijklmnop1234")", risk: [], rawJSON: nil
        )
        // JSON carries every event, so the leak has somewhere to show up.
        let url = directory.appendingPathComponent("audit.json")

        try ExportWriter.write(format: .json, sessions: sessions, events: [leaky], selection: selection, to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("sk-\("abcdefghijklmnop1234")"), "the token must not reach the file")
        XCTAssertTrue(text.contains("[redacted:openai-key]"))
    }

    func testDefaultPatternsCoverTheDocumentedSecrets() {
        let redactor = Redactor()
        // Built here, character runs only: pattern-shaped, obviously not real.
        let cases = [
            "sk-" + String(repeating: "a", count: 32),
            "ghp_" + String(repeating: "b", count: 36),
            "github_pat_" + String(repeating: "c", count: 30),
            "AKIA" + String(repeating: "D", count: 16),
            "xoxb-" + String(repeating: "1", count: 16),
            "-----BEGIN RSA " + "PRIVATE KEY-----\nMIIE\n-----END RSA " + "PRIVATE KEY-----",
            String(repeating: "A", count: 80),
        ]

        for secret in cases {
            let masked = redactor.redact("value: \(secret) end")
            XCTAssertTrue(masked.contains("[redacted:"), "not masked: \(secret.prefix(12))")
            XCTAssertFalse(masked.contains(secret), "kept verbatim: \(secret.prefix(12))")
        }
    }

    func testSuggestedFilename() {
        XCTAssertEqual(ExportWriter.suggestedFilename(format: .markdown, date: start), "trailwarden-2026-11-14.md")
        XCTAssertEqual(ExportWriter.suggestedFilename(format: .json, date: start), "trailwarden-2026-11-14.json")
    }
}
