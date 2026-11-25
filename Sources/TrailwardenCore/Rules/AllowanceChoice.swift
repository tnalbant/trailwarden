// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// What the Allow… sheet offers for one finding.
public enum AllowanceChoice {
    /// The scopes to offer, narrowest first. The project scope appears only when
    /// the event knows its folder; the pattern starts as the target and is edited
    /// by the reader.
    public static func scopes(for event: Event, hit _: RiskHit) -> [AllowanceScope] {
        let target = RuleEngine.target(for: event)
        var scopes: [AllowanceScope] = [.command(target)]
        if let cwd = event.cwd, !cwd.isEmpty {
            scopes.append(.projectRule(project: cwd))
        }
        scopes.append(.pattern(glob: target))
        scopes.append(.everywhere)
        return scopes
    }
}
