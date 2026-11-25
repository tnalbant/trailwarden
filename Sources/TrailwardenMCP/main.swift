// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

// A line-delimited JSON-RPC server on stdio — the Model Context Protocol shape,
// with four tools. Everything it answers comes from the local index, and there is
// no network code in this binary either.

var databasePath = EventStore.environmentOverride?.path ?? (try? EventStore.defaultURL().path)
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--db"), index + 1 < arguments.count {
    databasePath = arguments[index + 1]
}

guard let databasePath else {
    FileHandle.standardError.write(Data("trailwarden-mcp: no database path\n".utf8))
    exit(2)
}

let store: EventStore
do {
    store = try EventStore(url: URL(fileURLWithPath: databasePath))
} catch {
    FileHandle.standardError.write(Data("trailwarden-mcp: cannot open \(databasePath): \(error)\n".utf8))
    exit(2)
}

// After an update that changed the built-in rules, the history is re-graded
// once, so the answers use the rules this binary ships.
do {
    let engine = try RuleEngine(rules: RulePreferences.effectiveRules(), allowances: store.allowances())
    try store.reapplyRulesIfCatalogueChanged(engine: engine)
} catch {
    FileHandle.standardError.write(Data("trailwarden-mcp: cannot re-apply the rules: \(error)\n".utf8))
}

let router = MCPRouter(store: store)
FileHandle.standardError.write(Data("trailwarden-mcp \(TrailwardenVersion.current) ready\n".utf8))

while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    if let response = router.handle(line) {
        FileHandle.standardOutput.write(Data((response + "\n").utf8))
    }
}
