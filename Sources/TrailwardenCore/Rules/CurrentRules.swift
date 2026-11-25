// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

public extension RuleEngine {
    /// The engine that grades the index: `rules` with every stored allowance,
    /// the expired ones included (each still covers events from before its end).
    static func grading(_ store: EventStore, rules: [Rule]) throws -> RuleEngine {
        try RuleEngine(rules: rules, allowances: store.gradingAllowances())
    }
}

/// The rule engine a long-running watcher (the live guard, `trailwarden watch`)
/// grades with. It is rebuilt whenever the index's rules generation moves, so
/// an allowance or a rule switched off in the app reaches the next live pass
/// instead of being undone by it.
///
/// Not thread-safe: the owner calls it from one queue or under its own lock.
public final class CurrentRules {
    private let rules: () throws -> [Rule]
    private var engine: RuleEngine?
    private var generation: Int?

    /// `rules` is read again at every rebuild; by default the built-in rules
    /// with the reader's stored preferences.
    public init(rules: @escaping () throws -> [Rule] = RulePreferences.effectiveRules) {
        self.rules = rules
    }

    /// The engine for the current rules generation of `store`.
    public func engine(for store: EventStore) throws -> RuleEngine {
        let current = try store.rulesGeneration()
        if let engine, generation == current {
            return engine
        }
        let fresh = try RuleEngine.grading(store, rules: rules())
        engine = fresh
        generation = current
        return fresh
    }
}

public extension EventStore {
    /// Re-runs the rules over the stored index until the rules generation
    /// stops moving: an allowance stored or a rule changed while a pass runs
    /// gets a pass of its own instead of being lost. `rules` is read again at
    /// every pass. Returns the report of the last pass.
    @discardableResult
    func reapplyCurrentRules(
        _ rules: () throws -> [Rule] = RulePreferences.effectiveRules,
        maximumPasses: Int = 5) throws -> RuleRefreshReport
    {
        var report = RuleRefreshReport(events: 0, changed: 0, duration: 0)
        for _ in 0 ..< max(1, maximumPasses) {
            let generation = try rulesGeneration()
            report = try RuleEngine.grading(self, rules: rules()).reapply(to: self)
            if try rulesGeneration() == generation {
                break
            }
        }
        return report
    }
}
