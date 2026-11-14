// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import TrailwardenCore

@main
struct Trailwarden: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trailwarden",
        abstract: "Audit trail for coding agents on this Mac.",
        version: TrailwardenVersion.current
    )
}
