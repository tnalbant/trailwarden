// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import ArgumentParser
import Foundation
import TrailwardenCore

extension Severity: ExpressibleByArgument {}
extension RedactionLevel: ExpressibleByArgument {}

/// Where the index lives. Every command takes the same `--db` override so the
/// CLI can be pointed at a scratch database in tests and scripts.
struct StoreOptions: ParsableArguments {
    @Option(name: .long, help: "Index database path (default: Application Support/Trailwarden).")
    var db: String?

    var url: URL {
        get throws {
            if let db {
                return URL(fileURLWithPath: db)
            }
            return try EventStore.defaultURL()
        }
    }

    func open() throws -> EventStore {
        try EventStore(url: url)
    }
}

/// `--agent all|claude|codex`.
enum AgentOption: String, ExpressibleByArgument, CaseIterable {
    case all
    case claude
    case codex

    var agents: Set<Agent>? {
        switch self {
        case .all: nil
        case .claude: [.claudeCode]
        case .codex: [.codex]
        }
    }

    var list: [Agent] {
        agents.map { Array($0).sorted { $0.rawValue < $1.rawValue } } ?? []
    }
}

enum Output {
    static func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
        if !text.hasSuffix("\n") {
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    static func humanBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
