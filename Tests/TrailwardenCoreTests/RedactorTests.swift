// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

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
        XCTAssertEqual(Redactor.baseRules.count, 15)
        XCTAssertEqual(Redactor.strictRules.count, 2)
        XCTAssertEqual(Redactor.ruleCount, 17)
    }

    func testOpenAIKey() {
        XCTAssertEqual(
            normal.redact("export OPENAI_API_KEY=\(openAIKey)"),
            "export OPENAI_API_KEY=[redacted:openai-key]")
    }

    func testGitHubTokens() {
        XCTAssertEqual(
            normal.redact("token \(gitHubKey) done"),
            "token [redacted:github-token] done")
        XCTAssertEqual(normal.redact(gitHubPat), "[redacted:github-token]")
    }

    func testAWSKey() {
        XCTAssertEqual(
            normal.redact("aws_access_key_id = \(awsKey)"),
            "aws_access_key_id = [redacted:aws-key]")
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
            "Authorization: Bearer [redacted:bearer]")
        XCTAssertEqual(
            strict.redact("authorization: bearer \(token)"),
            "authorization: bearer [redacted:bearer]")
    }

    func testLongBlob() {
        let blob = String(repeating: "A", count: 80)
        XCTAssertEqual(normal.redact("cert \(blob) end"), "cert [redacted:blob] end")
    }

    func testLongPathIsNotABlob() {
        let path = "/Users/demo/Desktop/ExampleApp/Sources/ExampleAppCore/Protocol/FrameDecoder.swift"
        XCTAssertEqual(normal.redact("cat \(path)"), "cat \(path)")
        // A real base64 blob with an incidental slash is still masked.
        let blob = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu1SU1LfVLPHCozMxH2Mo4lgOEePzNm0tRgeLezV/ZRT"
        XCTAssertEqual(normal.redact("key \(blob)"), "key [redacted:blob]")
    }

    func testTheLiteralPrefilterNeverHidesAMatch() {
        XCTAssertTrue(Redactor.mayContain("x AKIA y", Array("akia".utf8)))
        XCTAssertTrue(Redactor.mayContain("Authorization: BEARER t", Array("bearer".utf8)))
        XCTAssertTrue(Redactor.mayContain("sk-", Array("sk-".utf8)))
        XCTAssertFalse(Redactor.mayContain("sk", Array("sk-".utf8)))
        XCTAssertFalse(Redactor.mayContain("nothing secret here", Array("xox".utf8)))
        XCTAssertTrue(Redactor.mayContain("ğüş xoxb", Array("xox".utf8)), "non-ASCII before the hint")
        // Every base rule with a hint, on its own fixture, behind a long line.
        let filler = String(repeating: "ordinary text ", count: 2000)
        for secret in [openAIKey, gitHubKey, gitHubPat, awsKey, slackKey] {
            XCTAssertFalse(normal.redact(filler + secret).contains(secret))
        }
    }

    func testAPrivateKeyCutBeforeItsFooterIsStillMasked() {
        // Previews are capped at 500 characters, so `cat ~/.ssh/id_rsa` keeps the
        // header and the first lines of the key, never the footer.
        let begin = "-----BEGIN OPENSSH " + "PRIVATE KEY-----"
        let body = String(repeating: "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ\n", count: 8)
        let cut = String("\(begin)\n\(body)".prefix(300))
        XCTAssertEqual(normal.redact("output: " + cut), "output: [redacted:private-key]")
    }

    func testMoreTokenShapes() {
        // Built from pieces: none of these is a real credential, and the file
        // itself must not trip a secret scanner.
        let cases: [(String, String)] = [
            ("AI" + "za" + String(repeating: "Q", count: 35), "[redacted:google-key]"),
            ("gl" + "pat-" + String(repeating: "g", count: 20), "[redacted:gitlab-token]"),
            ("sk" + "_live_" + String(repeating: "s", count: 24), "[redacted:stripe-key]"),
            ("np" + "m_" + String(repeating: "n", count: 36), "[redacted:npm-token]"),
            ("h" + "f_" + String(repeating: "h", count: 34), "[redacted:huggingface-token]"),
            (
                "ey" + "JhbGciOiJIUzI1NiJ9." + String(repeating: "p", count: 20) + "."
                    + String(repeating: "s", count: 20),
                "[redacted:jwt]")
        ]
        for (secret, label) in cases {
            XCTAssertEqual(normal.redact("value \(secret) end"), "value \(label) end", label)
        }
    }

    func testBearerInJSONAndInAURL() {
        let token = String(repeating: "t", count: 40)
        XCTAssertEqual(
            normal.redact(#"{"Authorization": "Bearer "# + token + #""}"#),
            #"{"Authorization": "Bearer [redacted:bearer]"}"#)
        XCTAssertEqual(
            normal.redact("git clone https://deploy:" + "hunter2secret@example.test/repo.git"),
            "git clone https://deploy:[redacted:password]@example.test/repo.git")
    }

    func testAURLPasswordWithAnAtOrASlashIsMaskedWhole() {
        // Built from parts so secret scanners do not read the fixture as a
        // real connection string.
        let scheme = "postgres" + "://"
        XCTAssertEqual(
            normal.redact("psql " + scheme + "app:" + "p@ss" + "@db.example.test:5432/main"),
            "psql " + scheme + "app:[redacted:password]" + "@db.example.test:5432/main")
        XCTAssertEqual(
            normal.redact("curl https://bot:" + "p/ss@example.test/a@b"),
            "curl https://bot:[redacted:password]@example.test/a@b")
        XCTAssertEqual(
            normal.redact("ssh://git@example.test:22/repo and https://example.test/u:x@y"),
            "ssh://git@example.test:22/repo and https://example.test/u:x@y",
            "no user:password part, nothing to mask")
    }

    func testABase64CredentialWithSlashesIsNotAPath() {
        // Random base64 with four slashes: short segments, but dense with digits
        // and capitals — the old "looks like a path" check let this through.
        let blob = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASC/BKcwggSjAgEAAoIBAQC7Vx3K9/q2Lm8Ndf5RtY1zP0aJ"
            + "/7HcXb3WkQ9eT2uV6sR8gY4L/1pM0nZoE5iFhD3jKw"
        XCTAssertEqual(normal.redact("key \(blob)"), "key [redacted:blob]")
        let relative = "Sources/TrailwardenCore/Localization/RuleLocalizationEntries/GeneratedTables/rules.swift"
        XCTAssertEqual(normal.redact("sed -n 1,80p \(relative)"), "sed -n 1,80p \(relative)")
    }

    func testEmailOnlyMaskedAtStrictLevel() {
        XCTAssertEqual(
            normal.redact("mail dev@example.com now"),
            "mail dev@example.com now")
        XCTAssertEqual(
            strict.redact("mail dev@example.com now"),
            "mail [redacted:email] now")
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
            "[redacted:aws-key] and [redacted:github-token]")
    }

    func testEventRedactionKeepsIdentityAndAbsolutePathsInStore() {
        let token = String(repeating: "f", count: 40)
        let event = makeEvent(
            command: "curl -H 'Authorization: Bearer \(token)' https://x.test",
            paths: ["/Users/demo/.ssh/id_rsa"],
            preview: "key \(openAIKey)")
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
        preview: String? = "hello") -> Event
    {
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
            rawJSON: "{\"note\":\"\(openAIKey)\"}")
    }
}
