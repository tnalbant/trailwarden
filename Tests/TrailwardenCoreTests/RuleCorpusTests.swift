// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// What the engine made of the corpus.
struct CorpusScore {
    var benignBashHits = 0
    var benignBashCritical = 0
    var benignFileHits = 0
    var riskyCaught = 0
    var benignBashTotal = 0
    var benignFileTotal = 0
    var riskyTotal = 0
    var falsePositivesByRule: [String: Int] = [:]
}

/// Loads the synthetic corpus under `Fixtures/rules-corpus`. Secret-shaped
/// placeholders are replaced with values built here from fragments, so no
/// credential-looking string is ever written into the repository.
enum RuleCorpus {
    static let placeholders: [String: String] = {
        let github = "ghp_" + String(repeating: "b", count: 36)
        let openAI = "sk-" + String(repeating: "a", count: 32)
        let anthropic = "sk-ant-" + "api03-" + String(repeating: "e", count: 32)
        let aws = "AKIA" + String(repeating: "D", count: 16)
        var table: [String: String] = [:]
        table["{{GITHUB_TOKEN}}"] = github
        table["{{OPENAI_KEY}}"] = openAI
        table["{{ANTHROPIC_KEY}}"] = anthropic
        table["{{AWS_KEY_ID}}"] = aws
        return table
    }()

    static func load() throws -> (
        benignBash: [String],
        benignFiles: [(tool: String, path: String)],
        risky: [(category: String, command: String)])
    {
        let benignBash = try lines("benign-bash.txt").map(decode)
        let benignFiles = try tabSeparated("benign-files.txt").map { (tool: $0.0, path: $0.1) }
        let risky = try tabSeparated("risky.txt").map { (category: $0.0, command: $0.1) }
        return (benignBash, benignFiles, risky)
    }

    /// Splits each line at the first TAB. A line without one is reported as a
    /// test failure naming the file and line, then skipped.
    private static func tabSeparated(_ name: String) throws -> [(String, String)] {
        var result: [(String, String)] = []
        for (index, line) in try lines(name).enumerated() {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                XCTFail("\(name) line \(index + 1) has no TAB separator")
                continue
            }
            result.append((parts[0], decode(parts[1])))
        }
        return result
    }

    private static func lines(_ name: String) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/rules-corpus/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Undoes the fixture escaping (`\n`, `\\`) and fills in the placeholders.
    private static func decode(_ raw: String) -> String {
        var out = ""
        var escaped = false
        for char in raw {
            if escaped {
                out.append(char == "n" ? "\n" : char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                out.append(char)
            }
        }
        for (placeholder, value) in placeholders {
            out = out.replacingOccurrences(of: placeholder, with: value)
        }
        return out
    }
}

final class RuleCorpusTests: XCTestCase {
    private func makeEvent(command: String?, tool: String = "Bash", paths: [String] = []) -> Event {
        Event(
            id: "event-\(UUID().uuidString)",
            ts: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .claudeCode,
            sessionId: "session-1",
            kind: .toolCall,
            tool: tool,
            command: command,
            paths: paths,
            preview: command,
            risk: [],
            rawJSON: nil)
    }

    func measure() throws -> CorpusScore {
        let corpus = try RuleCorpus.load()
        let engine = try RuleEngine.builtIn()
        var score = CorpusScore()
        score.benignBashTotal = corpus.benignBash.count
        score.benignFileTotal = corpus.benignFiles.count
        score.riskyTotal = corpus.risky.count

        for command in corpus.benignBash {
            let hits = engine.hits(for: makeEvent(command: command))
            if !hits.isEmpty {
                score.benignBashHits += 1
            }
            if hits.contains(where: { $0.severity == .critical }) {
                score.benignBashCritical += 1
            }
            for id in Set(hits.map(\.ruleId)) {
                score.falsePositivesByRule[id, default: 0] += 1
            }
        }
        for file in corpus.benignFiles {
            let hits = engine.hits(for: makeEvent(command: nil, tool: file.tool, paths: [file.path]))
            if !hits.isEmpty {
                score.benignFileHits += 1
            }
            for id in Set(hits.map(\.ruleId)) {
                score.falsePositivesByRule[id, default: 0] += 1
            }
        }
        for item in corpus.risky where !engine.hits(for: makeEvent(command: item.command)).isEmpty {
            score.riskyCaught += 1
        }
        return score
    }

    func testCorpusScoreIsPrinted() throws {
        let score = try measure()
        print(
            "RULE-CORPUS benignBash=\(score.benignBashHits)/\(score.benignBashTotal)"
                + " benignBashCritical=\(score.benignBashCritical)"
                + " benignFiles=\(score.benignFileHits)/\(score.benignFileTotal)"
                + " risky=\(score.riskyCaught)/\(score.riskyTotal)")
        for (id, count) in score.falsePositivesByRule.sorted(by: { $0.key < $1.key }) {
            print("RULE-CORPUS-FP \(id)=\(count)")
        }

        XCTAssertGreaterThan(score.benignBashTotal, 400)
        XCTAssertGreaterThan(score.benignFileTotal, 0)
        XCTAssertGreaterThan(score.riskyTotal, 200)

        let corpus = try RuleCorpus.load()
        var everything: [String] = corpus.benignBash
        everything.append(contentsOf: corpus.benignFiles.map(\.path))
        everything.append(contentsOf: corpus.risky.map(\.command))
        XCTAssertFalse(everything.contains { $0.contains("{{") }, "a placeholder survived loading")
    }

    // Frozen after the Task 6-7 rule tuning, 2026-11-23.
    // Baseline before tuning (CI run 45114571810):
    //   RULE-CORPUS benignBash=73/427 benignBashCritical=36 benignFiles=28/66 risky=160/216
    // Measured after tuning (CI run 45353727049):
    //   RULE-CORPUS benignBash=48/427 benignBashCritical=11 benignFiles=25/66 risky=173/216
    // Lower a ceiling or raise the floor when a rule change improves the score;
    // never loosen them to make a change pass.
    private let maxBenignBashHits = 48
    private let maxBenignBashCritical = 11
    private let maxBenignFileHits = 25
    private let minRiskyCaught = 173

    func testCorpusDoesNotRegress() throws {
        let score = try measure()
        XCTAssertLessThanOrEqual(score.benignBashHits, maxBenignBashHits, "benign Bash false alarms rose")
        XCTAssertLessThanOrEqual(score.benignBashCritical, maxBenignBashCritical, "benign Bash critical alerts rose")
        XCTAssertLessThanOrEqual(score.benignFileHits, maxBenignFileHits, "benign file false alarms rose")
        XCTAssertGreaterThanOrEqual(score.riskyCaught, minRiskyCaught, "risky catch rate fell")
    }
}
