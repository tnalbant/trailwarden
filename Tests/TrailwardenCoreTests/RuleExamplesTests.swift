// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// Every built-in rule documents what it is for with examples in `rules.json`,
/// and this test holds the engine to them.
///
/// - A rule with a command pattern (its own or in an alternative) has command
///   examples, run as Bash tool calls.
/// - A rule that only looks at paths has path examples, run as a file-tool
///   call on that path: the rule's own tool when it names one (the first of
///   `Write|Edit`), else `Read`.
///
/// Secret-shaped examples (R27) are written with the corpus placeholders —
/// `{{GITHUB_TOKEN}}`, `{{OPENAI_KEY}}`, `{{ANTHROPIC_KEY}}`, `{{AWS_KEY_ID}}` —
/// and expanded here from `RuleCorpus.placeholders`, because the secret scan
/// covers the whole git history and no credential-looking string may be in it.
final class RuleExamplesTests: XCTestCase {
    private func expand(_ example: String) -> String {
        var text = example
        for (placeholder, value) in RuleCorpus.placeholders {
            text = text.replacingOccurrences(of: placeholder, with: value)
        }
        return text
    }

    private func event(for example: String, of rule: Rule) -> Event {
        let usesCommands = !rule.match.allCommandPatterns.isEmpty
        var tool = "Bash"
        var command: String?
        if usesCommands {
            command = expand(example)
        } else {
            tool = rule.match.tool?.split(separator: "|").first.map(String.init) ?? "Read"
        }
        return Event(
            id: "example-\(UUID().uuidString)",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .claudeCode,
            sessionId: "examples",
            kind: .toolCall,
            tool: tool,
            command: command,
            paths: usesCommands ? [] : [example],
            preview: command,
            risk: [],
            rawJSON: nil)
    }

    func testEveryRuleHasExamplesThatBehave() throws {
        let rules = try RuleCatalog.builtIn()
        let engine = try RuleEngine(rules: rules)
        XCTAssertFalse(rules.isEmpty)

        for rule in rules {
            guard let examples = rule.examples else {
                XCTFail("\(rule.id) has no examples")
                continue
            }
            XCTAssertGreaterThanOrEqual(examples.matches.count, 2, "\(rule.id) needs two matching examples")
            XCTAssertGreaterThanOrEqual(examples.ignores.count, 1, "\(rule.id) needs an ignored example")

            for example in examples.matches {
                let ids = engine.hits(for: event(for: example, of: rule)).map(\.ruleId)
                XCTAssertTrue(ids.contains(rule.id), "\(rule.id) must hit: \(example) -> \(ids)")
            }
            for example in examples.ignores {
                let ids = engine.hits(for: event(for: example, of: rule)).map(\.ruleId)
                XCTAssertFalse(ids.contains(rule.id), "\(rule.id) must not hit: \(example) -> \(ids)")
            }
        }
    }

    func testExamplesNeverCarryALiteralSecret() throws {
        let engine = try RuleEngine.builtIn()
        for rule in try RuleCatalog.builtIn() {
            for example in (rule.examples?.matches ?? []) + (rule.examples?.ignores ?? []) {
                let hits = engine.evaluateCommand(example).map(\.ruleId)
                XCTAssertFalse(
                    hits.contains("R27"),
                    "write \(rule.id)'s example with a placeholder: \(example)")
            }
        }
    }
}
