// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

final class AgentSettingsScanTests: XCTestCase {
    private var home: URL!
    /// Built at runtime so the source holds no secret-shaped literal.
    private let secret = "ghp_" + String(repeating: "Q7w2", count: 9)

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tw-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func writeSettings(_ body: String) throws -> URL {
        let url = home.appendingPathComponent(".claude/settings.json")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private var leakyJSON: String {
        """
        {
          "permissions": {
            "allow": [
              "Bash(ls)",
              "Bash(curl -H 'Authorization: token \(secret)' https://example.com)"
            ]
          }
        }
        """
    }

    func testFindsATokenInAnAllowList() throws {
        let url = try writeSettings(leakyJSON)
        let findings = AgentSettingsScan.scan([url], home: home)
        XCTAssertEqual(findings.count, 1)
        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.line, 5)
        XCTAssertEqual(finding.ruleId, "R29")
        XCTAssertEqual(finding.severity, .warn)
        XCTAssertEqual(finding.path, "~/.claude/settings.json")
        XCTAssertFalse(finding.preview.contains(secret))
        XCTAssertTrue(finding.preview.contains("[redacted"))
        XCTAssertTrue(finding.key.hasPrefix("file:~/.claude/settings.json:R29:"))
    }

    func testMissingFilesAreSkipped() {
        let files = AgentSettingsScan.candidateFiles(home: home, sessionCwds: ["/nonexistent/project"])
        XCTAssertTrue(files.contains(home.appendingPathComponent(".codex/config.toml")))
        XCTAssertTrue(files.contains(URL(fileURLWithPath: "/nonexistent/project/.claude/settings.json")))
        XCTAssertEqual(AgentSettingsScan.scan(files, home: home), [])
    }

    func testSecretNeverStoredInClear() throws {
        let url = try writeSettings(leakyJSON)
        let store = try EventStore(inMemory: true)
        let findings = AgentSettingsScan.scan([url], home: home)
        try store.replaceFileFindings(findings, for: findings.map(\.path))

        let rows = try store.prepareRowStatement(
            "SELECT finding_key, path, rule_id, severity, line, preview, found_at FROM file_findings")
        var seen = 0
        while try rows.step() {
            seen += 1
            for column in Int32(0) ..< 7 {
                XCTAssertFalse((rows.text(column) ?? "").contains(secret), "column \(column)")
            }
        }
        XCTAssertEqual(seen, 1)

        let snapshot = try Inbox.load(from: store)
        XCTAssertEqual(snapshot.unreviewed.count, 1)
        for item in snapshot.unreviewed {
            XCTAssertFalse(item.id.contains(secret))
            if case let .file(path, _, preview) = item.source {
                XCTAssertFalse(path.contains(secret))
                XCTAssertFalse(preview.contains(secret))
            }
        }
    }

    func testRemovedSecretDisappears() throws {
        let url = try writeSettings(leakyJSON)
        let store = try EventStore(inMemory: true)
        try AgentSettingsScan.refresh(store: store, home: home, sessionCwds: [])
        XCTAssertEqual(try Inbox.load(from: store).unreviewed.count, 1)

        _ = try writeSettings("{ \"permissions\": { \"allow\": [\"Bash(ls)\"] } }")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try AgentSettingsScan.refresh(store: store, home: home, sessionCwds: [])
        XCTAssertEqual(try Inbox.load(from: store).unreviewed.count, 0)
    }

    func testAllowanceHidesAFileFinding() throws {
        let url = try writeSettings(leakyJSON)
        let store = try EventStore(inMemory: true)
        try AgentSettingsScan.refresh(store: store, home: home, sessionCwds: [])
        XCTAssertEqual(try Inbox.load(from: store).unreviewed.count, 1)
        _ = url
        try store.addAllowance(Allowance(ruleId: "R29", scope: .pattern(glob: "~/.claude/*"), until: nil))
        XCTAssertEqual(try Inbox.load(from: store).unreviewed.count, 0)
    }

    func testOrphanFileReviewIsPruned() throws {
        let store = try EventStore(inMemory: true)
        try store.setReview(.reviewed, for: "file:~/gone.json:R29:abcdef123456")
        try store.removeOrphanEventReviews()
        let states = try store.reviewStates(for: ["file:~/gone.json:R29:abcdef123456"])
        XCTAssertEqual(states.values.first, ReviewState.new)
    }

    func testSecretLinesReportLineNumbers() {
        let text = "a\nb \(secret)\nc"
        let lines = Redactor().secretLines(in: text)
        XCTAssertEqual(lines.map(\.line), [2])
        XCTAssertFalse(lines[0].redacted.contains(secret))
    }
}
