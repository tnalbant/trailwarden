// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct RulesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules",
        abstract: "Inspect the rule set or test a command against it.",
        subcommands: [RulesList.self, RulesTest.self, RulesApply.self])
}

struct RulesList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Print the rules Trailwarden ships with.")

    @Flag(name: .long, help: "Print the rule set as JSON.")
    var json = false

    func run() throws {
        let rules = try RuleCatalog.builtIn()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try print(String(decoding: encoder.encode(rules), as: UTF8.self))
            return
        }
        for rule in rules.sorted(by: { Self.number(of: $0.id) < Self.number(of: $1.id) }) {
            let severity = rule.severity.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            let state = rule.isEnabled ? "" : "  (disabled)"
            let title = RuleLocalization.text(forRule: rule.id, language: .english)?.title ?? rule.title
            print("\(rule.id.padding(toLength: 4, withPad: " ", startingAt: 0))\(severity)  \(title)\(state)")
        }
    }

    /// R2 before R10, not after it.
    private static func number(of id: String) -> Int {
        Int(id.drop(while: { !$0.isNumber })) ?? Int.max
    }
}

struct RulesTest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Check one command against the rule set.")

    @Argument(help: "Shell command to evaluate.")
    var command: String

    @Option(name: .long, help: "Tool name to evaluate as.")
    var tool = "Bash"

    func run() throws {
        let engine = try RuleEngine.builtIn()
        let hits = engine.evaluateCommand(command, tool: tool)
        if hits.isEmpty {
            print("clean - no rule matched")
            return
        }
        for hit in hits {
            print("\(hit.severity.rawValue)  \(hit.ruleId)  \(hit.englishMessage)")
        }
    }
}

/// Re-runs the rules over everything already in the index — after an update
/// that ships new rules, or after a change in the Rules window.
struct RulesApply: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Re-run the rule set over the whole index.")

    @OptionGroup var store: StoreOptions

    func run() throws {
        let database = try store.open()
        let builtIn = try RuleCatalog.builtIn()
        let stored = try (try? RulePreferences.defaultURL()).map { try RulePreferences.load(from: $0) } ?? []
        let engine = try RuleEngine.grading(database, rules: RulePreferences.apply(stored, to: builtIn))
        let report = try engine.reapply(to: database)
        print(String(
            format: "%d events checked, %d changed, %.2f s",
            report.events, report.changed, report.duration))
    }
}
