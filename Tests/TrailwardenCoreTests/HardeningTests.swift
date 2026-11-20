// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// Inputs that used to crash or leak: a duplicated preference, an absurd
/// number from another program's database, a world-readable moment on export,
/// a user name left in an exported preview.
final class HardeningTests: XCTestCase {
    func testADuplicatedPreferenceDoesNotCrash() throws {
        let rules = try RuleCatalog.builtIn()
        let preferences = [
            RulePreference(id: "R1", enabled: true, severity: .critical),
            RulePreference(id: "R1", enabled: false, severity: .warn)
        ]
        let applied = RulePreferences.apply(preferences, to: rules)
        XCTAssertEqual(applied.first { $0.id == "R1" }?.isEnabled, false, "the last entry wins")
    }

    func testOddNumbersSaturateInsteadOfTrapping() {
        XCTAssertEqual(Int(saturating: .nan), 0)
        XCTAssertEqual(Int(saturating: .infinity), .max)
        XCTAssertEqual(Int(saturating: 1e30), .max)
        XCTAssertEqual(Int(saturating: -1e30), .min)
        XCTAssertEqual(Int(saturating: 1234.9), 1234)
    }

    func testPrivateFilesAreNeverWorldReadable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("private-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try PrivateFile.write(Data("first".utf8), to: url)
        try PrivateFile.write(Data("second".utf8), to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second", "replaced, not appended")
        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(".\(url.lastPathComponent).") }
        XCTAssertTrue(leftovers.isEmpty, "no temporary file stays behind")
    }

    func testAnExportedPreviewLosesTheUserName() {
        let event = Event(
            id: "e",
            ts: Date(timeIntervalSince1970: 0),
            agent: .copilot,
            sessionId: "s",
            kind: .toolCall,
            gitBranch: "fix/token-ghp_" + String(repeating: "a", count: 36),
            tool: "view",
            paths: ["/Users/demo/dev/app/README.md"],
            preview: "/Users/demo/dev/app/README.md")
        let exported = Redactor().redactForExport(event)
        XCTAssertEqual(exported.preview, "~/dev/app/README.md")
        XCTAssertEqual(
            exported.gitBranch,
            "fix/token-[redacted:github-token]",
            "a branch name can hold a token")
    }
}
