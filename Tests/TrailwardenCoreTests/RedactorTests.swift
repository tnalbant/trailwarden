// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

/// Every fixture here is deliberately synthetic: long runs of one character that
/// match the pattern but could never be somebody's real credential. The home
/// directory is `/Users/demo`, so the file carries no personal path either.
final class RedactorTests: XCTestCase {
    private let normal = Redactor(level: .normal)
    private let strict = Redactor(level: .strict)

    private let openAIKey = "sk-" + String(repeating: "a", count: 32)
    private let gitHubKey = "ghp_" + String(repeating: "b", count: 36)
    private let gitHubPat = "github_pat_" + String(repeating: "c", count: 30)
    private let awsKey = "AKIA" + String(repeating: "D", count: 16)
    private let slackKey = "xoxb-" + String(repeating: "1", count: 16)

    func testEveryRuleCompiled() {
        // A pattern that fails to compile would silently disappear from the
        // masking pass, so the count is asserted, not assumed.
        XCTAssertEqual(Redactor.baseRules.count, 8)
        XCTAssertEqual(Redactor.strictRules.count, 2)
        XCTAssertEqual(Redactor.ruleCount, 10)
    }

    func testOpenAIKey() {
        XCTAssertEqual(
            normal.redact("export OPENAI_API_KEY=\(openAIKey)"),
            "export OPENAI_API_KEY=[redacted:openai-key]"
        )
    }

    func testGitHubTokens() {
        XCTAssertEqual(
            normal.redact("token \(gitHubKey) done"),
            "token [redacted:github-token] done"
        )
        XCTAssertEqual(normal.redact(gitHubPat), "[redacted:github-token]")
    }

    func testAWSKey() {
        XCTAssertEqual(
            normal.redact("aws_access_key_id = \(awsKey)"),
            "aws_access_key_id = [redacted:aws-key]"
        )
    }

    func testSlackToken() {
        XCTAssertEqual(normal.redact(slackKey), "[redacted:slack-token]")
    }

    func testPrivateKeyBlockIsRemovedWhole() {
        // Built from pieces so the file itself never contains a key marker.
        let begin = "-----BEGIN RSA " + "PRIVATE KEY-----"
        let end = "-----END RSA " + "PRIVATE KEY-----"
        let text = "before\n\(begin)\nMIIEowIBAAKCAQEA\n\(end)\nafter"

        XCTAssertEqual(normal.redact(text), "before\n[redacted:private-key]\nafter")
    }

    func testBearerHeader() {
        // The token has to look like one, otherwise the rule never fires and a
        // "nothing changed" assertion would pass for the wrong reason.
        let token = String(repeating: "e", count: 40)
        XCTAssertEqual(
            normal.redact("Authorization: Bearer \(token)"),
            "Authorization: Bearer [redacted:bearer]"
        )
        XCTAssertEqual(
            strict.redact("authorization: bearer \(token)"),
            "authorization: bearer [redacted:bearer]"
        )
    }

    func testLongBlob() {
        let blob = String(repeating: "A", count: 80)
        XCTAssertEqual(normal.redact("cert \(blob) end"), "cert [redacted:blob] end")
    }

    func testEmailOnlyMaskedAtStrictLevel() {
        XCTAssertEqual(
            normal.redact("mail dev@example.com now"),
            "mail dev@example.com now"
        )
        XCTAssertEqual(
            strict.redact("mail dev@example.com now"),
            "mail [redacted:email] now"
        )
    }

    func testHomePathIsShortened() {
        XCTAssertEqual(normal.shortenHome("/Users/demo/dev/trailwarden"), "~/dev/trailwarden")
        XCTAssertEqual(normal.shortenHome("/opt/homebrew/bin/swift"), "/opt/homebrew/bin/swift")
    }

    func testOrdinaryCommandsAreUntouched() {
        let text = "rm -rf ./build && swift test --filter Store"
        XCTAssertEqual(normal.redact(text), text)
        XCTAssertEqual(strict.redact(text), text)
    }

    func testSeveralSecretsInOneLine() {
        XCTAssertEqual(
            normal.redact("\(awsKey) and \(gitHubKey)"),
            "[redacted:aws-key] and [redacted:github-token]"
        )
    }

    func testEventRedactionKeepsIdentityAndAbsolutePathsInStore() {
        let token = String(repeating: "f", count: 40)
        let event = makeEvent(
            command: "curl -H 'Authorization: Bearer \(token)' https://x.test",
            paths: ["/Users/demo/.ssh/id_rsa"],
            preview: "key \(openAIKey)"
        )
        let stored = normal.redact(event)

        XCTAssertEqual(stored.id, event.id)
        XCTAssertEqual(stored.kind, event.kind)
        XCTAssertEqual(stored.tool, event.tool)
        XCTAssertEqual(stored.command, "curl -H 'Authorization: Bearer [redacted:bearer]' https://x.test")
        XCTAssertEqual(stored.preview, "key [redacted:openai-key]")
        XCTAssertEqual(stored.paths, ["/Users/demo/.ssh/id_rsa"], "the store keeps the real path")
        XCTAssertFalse(stored.rawJSON?.contains(openAIKey) ?? false, "the raw line is masked too")
    }

    func testExportRedactionShortensPaths() {
        let exported = normal.redactForExport(makeEvent(paths: ["/Users/demo/.ssh/id_rsa"]))
        XCTAssertEqual(exported.paths, ["~/.ssh/id_rsa"])
    }

    // MARK: - Helper

    private func makeEvent(
        command: String? = "ls",
        paths: [String] = [],
        preview: String? = "hello"
    ) -> Event {
        Event(
            id: "event-1",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .claudeCode,
            sessionId: "session-1",
            kind: .toolCall,
            cwd: "/Users/demo/dev/demo",
            gitBranch: "main",
            tool: "Bash",
            command: command,
            paths: paths,
            preview: preview,
            risk: [],
            rawJSON: "{\"note\":\"\(openAIKey)\"}"
        )
    }
}
