// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class RedactorTests: XCTestCase {
    private let normal = Redactor(level: .normal)
    private let strict = Redactor(level: .strict)

    func testEveryRuleCompiled() {
        // A pattern that fails to compile would silently disappear from the
        // masking pass, so the count is asserted, not assumed.
        XCTAssertEqual(Redactor.baseRules.count, 8)
        XCTAssertEqual(Redactor.strictRules.count, 2)
        XCTAssertEqual(Redactor.ruleCount, 10)
    }

    func testOpenAIKey() {
        XCTAssertEqual(
            normal.redact("export OPENAI_API_KEY=sk-proj-AbCdEf0123456789XyZ"),
            "export OPENAI_API_KEY=[redacted:openai-key]"
        )
    }

    func testGitHubTokens() {
        XCTAssertEqual(
            normal.redact("token ghp_1234567890abcdefghijABCDEFGHIJ123456 done"),
            "token [redacted:github-token] done"
        )
        XCTAssertEqual(
            normal.redact("github_pat_11ABCDEFG0123456789_abcdefghijklmnop"),
            "[redacted:github-token]"
        )
    }

    func testAWSKey() {
        XCTAssertEqual(
            normal.redact("aws_access_key_id = AKIAIOSFODNN7EXAMPLE"),
            "aws_access_key_id = [redacted:aws-key]"
        )
    }

    func testSlackToken() {
        XCTAssertEqual(
            normal.redact("xoxb-1234567890-abcdefghij"),
            "[redacted:slack-token]"
        )
    }

    func testPrivateKeyBlockIsRemovedWhole() {
        let text = """
        before
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAAB
        -----END OPENSSH PRIVATE KEY-----
        after
        """
        let redacted = normal.redact(text)

        XCTAssertEqual(redacted, "before\n[redacted:private-key]\nafter")
    }

    func testBearerHeader() {
        XCTAssertEqual(
            normal.redact("Authorization: Bearer eyJhbGciOi.abc-123"),
            "Authorization: Bearer [redacted:bearer]"
        )
    }

    func testLongBlob() {
        let blob = String(repeating: "A", count: 80)
        XCTAssertEqual(normal.redact("cert \(blob) end"), "cert [redacted:blob] end")
    }

    func testEmailOnlyMaskedAtStrictLevel() {
        XCTAssertEqual(
            normal.redact("mail turgay@example.com now"),
            "mail turgay@example.com now"
        )
        XCTAssertEqual(
            strict.redact("mail turgay@example.com now"),
            "mail [redacted:email] now"
        )
    }

    func testHomePathIsShortened() {
        XCTAssertEqual(
            normal.shortenHome("/Users/underline/dev/trailwarden"),
            "~/dev/trailwarden"
        )
        XCTAssertEqual(
            normal.shortenHome("/opt/homebrew/bin/swift"),
            "/opt/homebrew/bin/swift"
        )
    }

    func testOrdinaryCommandsAreUntouched() {
        let text = "rm -rf ./build && swift test --filter Store"
        XCTAssertEqual(normal.redact(text), text)
        XCTAssertEqual(strict.redact(text), text)
    }

    func testSeveralSecretsInOneLine() {
        let text = "AKIAIOSFODNN7EXAMPLE and ghp_1234567890abcdefghijABCDEFGHIJ123456"
        XCTAssertEqual(
            normal.redact(text),
            "[redacted:aws-key] and [redacted:github-token]"
        )
    }

    func testEventRedactionKeepsIdentityAndAbsolutePathsInStore() {
        let event = makeEvent(
            command: "curl -H 'Authorization: Bearer sekret' https://x",
            paths: ["/Users/underline/.ssh/id_rsa"],
            preview: "key sk-proj-AbCdEf0123456789XyZ"
        )
        let stored = normal.redact(event)

        XCTAssertEqual(stored.id, event.id)
        XCTAssertEqual(stored.kind, event.kind)
        XCTAssertEqual(stored.tool, event.tool)
        XCTAssertEqual(stored.command, "curl -H 'Authorization: Bearer [redacted:bearer]' https://x")
        XCTAssertEqual(stored.preview, "key [redacted:openai-key]")
        XCTAssertEqual(stored.paths, ["/Users/underline/.ssh/id_rsa"], "the store keeps the real path")
        XCTAssertFalse(stored.rawJSON?.contains("sk-proj") ?? false)
    }

    func testExportRedactionShortensPaths() {
        let event = makeEvent(paths: ["/Users/underline/.ssh/id_rsa"])
        let exported = normal.redactForExport(event)

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
            cwd: "/Users/underline/dev/demo",
            gitBranch: "main",
            tool: "Bash",
            command: command,
            paths: paths,
            preview: preview,
            risk: [],
            rawJSON: "{\"note\":\"sk-proj-AbCdEf0123456789XyZ\"}"
        )
    }
}
