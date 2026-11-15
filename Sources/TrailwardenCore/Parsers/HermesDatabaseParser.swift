// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import SQLite3

/// A source that is a database, not a folder of transcript files.
public struct DatabaseSource: Sendable {
    public let database: URL
    public let parser: any DatabaseAgentParser

    public var agent: Agent { parser.agent }

    public init(database: URL, parser: any DatabaseAgentParser) {
        self.database = database
        self.parser = parser
    }
}

/// Parsers for agents that keep their history in SQLite.
public protocol DatabaseAgentParser: Sendable {
    var agent: Agent { get }
    func parse(database: URL, since: Date?) throws -> ParseResult
}

/// Hermes Agent writes every turn into `~/.hermes/state.db`:
///
/// - `sessions(id, cwd, model, started_at, input_tokens, output_tokens, …)`
/// - `messages(session_id, role, content, tool_name, tool_calls, timestamp, …)`
///
/// User turns become `.message` events, assistant tool calls become `.toolCall`
/// events with their arguments, and each session contributes one `.tokenUsage`
/// counter so the usage screen has numbers for this agent too. Tool results are
/// not stored: they are the bulk of the file and the least useful part of an
/// audit trail.
public struct HermesDatabaseParser: DatabaseAgentParser {
    public init() {}

    public var agent: Agent { .hermes }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/state.db")
    }

    private static let previewLimit = 500
    private static let commandKeys = ["command", "cmd", "shell_command"]
    private static let pathKeys = ["path", "file_path", "absolute_path", "target_file", "directory"]

    public func parse(database url: URL, since: Date?) throws -> ParseResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ParseResult(events: [], skippedLines: 0)
        }

        var handle: OpaquePointer?
        // Read-only and immutable: Hermes owns this file, we only look at it.
        let uri = "file:\(url.path)?immutable=1"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let handle else {
            throw TranscriptError.unreadable(url.lastPathComponent)
        }
        defer { sqlite3_close(handle) }

        var sessions: [String: (cwd: String?, started: Date)] = [:]
        var events: [Event] = []
        var skipped = 0

        let cutoff = since ?? .distantPast
        var tokenEvents: [Event] = []

        try query(
            handle,
            """
            SELECT id, cwd, started_at, input_tokens, output_tokens FROM sessions
            WHERE started_at >= ?
            """,
            since: cutoff
        ) { row in
            guard let id = row.text(0) else { return }
            let cwd = row.text(1)
            let started = Date(timeIntervalSince1970: row.double(2))
            sessions[id] = (cwd, started)

            let input = Int(row.double(3))
            let output = Int(row.double(4))
            guard input > 0 || output > 0 else { return }
            tokenEvents.append(Event(
                id: "hermes:\(id):tokens",
                ts: started,
                agent: .hermes,
                sessionId: id,
                kind: .tokenUsage,
                cwd: cwd,
                tool: nil,
                command: nil,
                paths: [],
                preview: "tokens: \(input) in / \(output) out",
                risk: [],
                rawJSON: nil
            ))
        }

        try query(
            handle,
            """
            SELECT id, session_id, role, content, tool_name, tool_calls, timestamp FROM messages
            WHERE timestamp >= ? AND active = 1 AND role IN ('user', 'assistant')
            ORDER BY timestamp
            """,
            since: cutoff
        ) { row in
            guard let sessionId = row.text(1), let role = row.text(2) else { return }
            let messageId = Int(row.double(0))
            let ts = Date(timeIntervalSince1970: row.double(6))
            let cwd = sessions[sessionId]?.cwd
            let content = row.text(3)

            if role == "user" {
                guard let content, !content.isEmpty else { return }
                events.append(Event(
                    id: "hermes:\(sessionId):\(messageId):u",
                    ts: ts,
                    agent: .hermes,
                    sessionId: sessionId,
                    kind: .message,
                    cwd: cwd,
                    preview: Self.trim(content),
                    risk: [],
                    rawJSON: nil
                ))
                return
            }

            guard let calls = row.text(5), let parsed = Self.toolCalls(from: calls) else { return }
            for (index, call) in parsed.enumerated() {
                guard let event = Self.event(
                    call: call,
                    id: "hermes:\(sessionId):\(messageId):\(index)",
                    ts: ts,
                    sessionId: sessionId,
                    cwd: cwd
                ) else {
                    // A call with no command and no path (a todo update, a memory
                    // write) is simply not an audit event — not a parse failure.
                    continue
                }
                events.append(event)
            }
        }

        return ParseResult(events: events + tokenEvents, skippedLines: skipped)
    }

    // MARK: - Helpers

    private static func event(
        call: [String: Any],
        id: String,
        ts: Date,
        sessionId: String,
        cwd: String?
    ) -> Event? {
        // Two shapes in the wild: {"name": …, "arguments": …} and the OpenAI
        // wrapper {"type":"function","function":{"name":…,"arguments":…}}.
        let function = call["function"] as? [String: Any]
        guard let name = (call["name"] as? String) ?? (function?["name"] as? String) else { return nil }
        let rawArguments = call["arguments"] ?? function?["arguments"]
        let arguments = (rawArguments as? String).flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? rawArguments as? [String: Any]
            ?? [:]

        let command = commandKeys.compactMap { arguments[$0] as? String }.first
        let paths = pathKeys.compactMap { arguments[$0] as? String }
        guard command != nil || !paths.isEmpty else { return nil }

        return Event(
            id: id,
            ts: ts,
            agent: .hermes,
            sessionId: sessionId,
            kind: .toolCall,
            cwd: cwd,
            tool: name,
            command: command,
            paths: paths,
            preview: command ?? paths.first,
            risk: [],
            rawJSON: nil
        )
    }

    private static func toolCalls(from text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = object as? [[String: Any]] { return array }
        if let wrapper = object as? [String: Any],
           let array = wrapper["tool_calls"] as? [[String: Any]] {
            return array
        }
        return nil
    }

    private static func trim(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > previewLimit ? String(flat.prefix(previewLimit)) + "…" : flat
    }

    private func query(
        _ handle: OpaquePointer,
        _ sql: String,
        since: Date? = nil,
        row: (Row) -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TranscriptError.unreadable(sqlite3_errmsg(handle).map { String(cString: $0) } ?? "sql")
        }
        defer { sqlite3_finalize(statement) }
        if sql.contains("?") {
            sqlite3_bind_double(statement, 1, (since ?? .distantPast).timeIntervalSince1970)
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            row(Row(statement: statement))
        }
    }

    private struct Row {
        let statement: OpaquePointer

        func text(_ index: Int32) -> String? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  let cString = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: cString)
        }

        func double(_ index: Int32) -> Double {
            sqlite3_column_double(statement, index)
        }
    }
}
