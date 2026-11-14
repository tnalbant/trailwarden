// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

struct RulesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rules",
        abstract: "Inspect the rule set or test a command against it.",
        subcommands: [RulesList.self, RulesTest.self]
    )
}

struct RulesList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Print the rules Trailwarden ships with."
    )

    @Flag(name: .long, help: "Print the rule set as JSON.")
    var json = false

    func run() throws {
        let rules = try RuleCatalog.builtIn()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(rules), as: UTF8.self))
            return
        }
        for rule in rules.sorted(by: { Self.number(of: $0.id) < Self.number(of: $1.id) }) {
            let severity = rule.severity.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
            let state = rule.isEnabled ? "" : "  (disabled)"
            print("\(rule.id.padding(toLength: 4, withPad: " ", startingAt: 0))\(severity)  \(rule.title)\(state)")
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
        abstract: "Check one command against the rule set."
    )

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
            print("\(hit.severity.rawValue)  \(hit.ruleId)  \(hit.message)")
        }
    }
}
