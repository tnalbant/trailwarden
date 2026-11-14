// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import TrailkeepCore

@main
struct Trailkeep: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trailkeep",
        abstract: "Audit trail for coding agents on this Mac.",
        version: TrailkeepVersion.current
    )
}
