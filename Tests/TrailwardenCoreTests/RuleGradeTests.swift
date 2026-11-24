// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// Destructive commands written flags-first, quoted, with clustered short flags
/// or through a less common reader must keep the rule and the severity they had
/// before the 0.2.5 false-alarm work, and no pattern may backtrack badly.
final class RuleGradeTests: XCTestCase {
    func testFlagFirstQuotedAndClusteredDestructiveCommandsKeepTheirGrade() throws {
        let engine = try RuleEngine(rules: RuleCatalog.builtIn())
        let cases: [(command: String, rule: String, severity: Severity)] = [
            ("kubectl delete --all pods", "R25", .critical),
            ("kubectl delete --all", "R25", .critical),
            ("kubectl delete -n prod deployment api", "R25", .critical),
            ("kubectl delete -n prod ns x", "R25", .critical),
            ("terraform apply -destroy -auto-approve", "R25", .critical),
            ("kubectl delete pod api-123", "R28", .warn),
            ("terraform apply -auto-approve", "R28", .warn),
            ("git push --force origin 'main'", "R5", .warn),
            ("git push --force origin \"main\"", "R5", .warn),
            ("git push -fu origin main", "R5", .warn),
            ("git push origin --delete 'main'", "R5", .warn),
            ("grep -r x ~/.ssh", "R4", .critical),
            ("rg x ~/.ssh", "R4", .critical),
            ("find ~/.ssh -exec cat {} \\;", "R4", .critical),
            ("sed -n 1p ~/.ssh/id_rsa", "R4", .critical),
            ("awk 1 ~/.aws/credentials", "R4", .critical),
            ("dd if=~/.ssh/id_rsa of=/tmp/k", "R4", .critical),
            ("diff ~/.ssh/id_rsa /tmp/k", "R4", .critical),
            ("nl ~/.ssh/id_rsa", "R4", .critical),
            ("od -c ~/.ssh/id_rsa", "R4", .critical),
            ("tac ~/.aws/credentials", "R4", .critical),
            ("sort ~/.aws/credentials", "R4", .critical),
            ("cut -c1-5 ~/.ssh/id_rsa", "R4", .critical),
            ("vim ~/.ssh/id_rsa", "R4", .critical),
            ("source ~/.aws/credentials", "R4", .critical)
        ]
        for (command, rule, severity) in cases {
            let hits = engine.evaluateCommand(command)
            XCTAssertEqual(hits.map(\.ruleId), [rule], command)
            XCTAssertEqual(hits.first?.severity, severity, command)
        }
        let quiet = ["ls ~/.ssh", "ls ~/.aws", "git push -fu origin feature/x", "git push -d origin old-x"]
        for command in quiet {
            XCTAssertTrue(engine.evaluateCommand(command).isEmpty, "must stay quiet: \(command)")
        }
    }

    /// Two adjacent unbounded runs (`[^;&|\n]*\s-d\b[^;&|\n]*\s…`) backtrack
    /// quadratically: the review measured ~10 s for 40 KB of `-d x` against the
    /// first 0.2.5 R5. Every built-in command pattern is run on its own here, with
    /// the engine's options, so path matching does not blur the timing. A linear
    /// pattern takes milliseconds; the 1 s bound is generous for a slow runner
    /// and still far below what a quadratic pattern needs at this size.
    func testLongArgumentListsDoNotBacktrack() throws {
        let patterns = try RuleCatalog.builtIn().flatMap { rule in
            rule.match.allCommandPatterns.map { (rule.id, $0) }
        }
        let inputs = [" -d x", " -f x", " :x", " --delete x", " -n 1 x", " -n x", " a=b"].map { unit in
            "git push" + String(repeating: unit, count: 40000 / unit.count)
        }
        for (id, pattern) in patterns {
            let regex = try NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .anchorsMatchLines])
            for input in inputs {
                let start = Date()
                _ = RuleEngine.matches(regex, input)
                let elapsed = Date().timeIntervalSince(start)
                XCTAssertLessThan(elapsed, 1, "\(id) is slow on \(input.prefix(16))…")
            }
        }
    }
}
