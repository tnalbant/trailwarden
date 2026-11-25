// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation
import SQLite3

/// A source that is a database, not a folder of transcript files.
public struct DatabaseSource: Sendable {
    public let database: URL
    public let parser: any DatabaseAgentParser

    public var agent: Agent {
        parser.agent
    }

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

    public var agent: Agent {
        .hermes
    }

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
        // Read-only, but not `immutable=1`: Hermes writes to this database while
        // it runs (WAL), and immutable tells SQLite to ignore the WAL and every
        // lock. `mode=ro` reads a consistent snapshot instead.
        let uri = "file:\(url.path)?mode=ro"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let handle
        else {
            throw TranscriptError.unreadable(url.lastPathComponent)
        }
        defer { sqlite3_close(handle) }

        var sessions: [String: (cwd: String?, started: Date)] = [:]
        var events: [Event] = []

        let cutoff = since ?? .distantPast

        // Every session, not only those started since the last pass: a session
        // that began yesterday and is still running needs its folder for today's
        // messages and its growing token count. The table is one row per session.
        var tokenCandidates: [String: Event] = [:]
        // Cache, reasoning and model columns are newer than the table; a
        // missing one reads as 0 (or no model) instead of failing the pass.
        var columns = Set<String>()
        try query(handle, "PRAGMA table_info(sessions)") { row in
            if let name = row.text(1) {
                columns.insert(name)
            }
        }
        func column(_ name: String) -> String {
            columns.contains(name) ? name : "NULL"
        }
        try query(
            handle,
            """
            SELECT id, cwd, started_at, input_tokens, output_tokens, \(column("cache_read_tokens")),
                   \(column("cache_write_tokens")), \(column("reasoning_tokens")), \(column("model"))
            FROM sessions
            """) { row in
                guard let id = row.text(0) else { return }
                let cwd = row.text(1)
                let started = Date(timeIntervalSince1970: row.double(2))
                sessions[id] = (cwd, started)

                let usage = TokenCount(
                    model: row.text(8),
                    input: Int(saturating: row.double(3)),
                    output: Int(saturating: row.double(4)),
                    cacheRead: Int(saturating: row.double(5)),
                    cacheWrite: Int(saturating: row.double(6)),
                    reasoning: Int(saturating: row.double(7)))
                guard !usage.isEmpty else { return }
                tokenCandidates[id] = Event(
                    id: "hermes:\(id):tokens",
                    ts: started,
                    agent: .hermes,
                    sessionId: id,
                    kind: .tokenUsage,
                    cwd: cwd,
                    preview: usage.preview,
                    usage: usage)
            }
        var activeSessions = Set<String>()
        var collector = TitleCollector()

        try query(
            handle,
            """
            SELECT id, session_id, role, content, tool_name, tool_calls, timestamp FROM messages
            WHERE timestamp >= ? AND active = 1 AND role IN ('user', 'assistant')
            ORDER BY timestamp
            """,
            since: cutoff)
        { row in
            guard let sessionId = row.text(1), let role = row.text(2) else { return }
            activeSessions.insert(sessionId)
            let messageId = Int(saturating: row.double(0))
            let ts = Date(timeIntervalSince1970: row.double(6))
            let cwd = sessions[sessionId]?.cwd
            let content = row.text(3)

            if role == "user" {
                guard let content, !content.isEmpty else { return }
                collector.firstMessage(content, session: sessionId)
                events.append(Event(
                    id: "hermes:\(sessionId):\(messageId):u",
                    ts: ts,
                    agent: .hermes,
                    sessionId: sessionId,
                    kind: .message,
                    cwd: cwd,
                    preview: Self.trim(content),
                    risk: [],
                    rawJSON: nil))
                return
            }

            guard let calls = row.text(5), let parsed = Self.toolCalls(from: calls) else { return }
            for (index, call) in parsed.enumerated() {
                guard let event = Self.event(
                    call: call,
                    id: "hermes:\(sessionId):\(messageId):\(index)",
                    ts: ts,
                    sessionId: sessionId,
                    cwd: cwd)
                else {
                    // A call with no command and no path (a todo update, a memory
                    // write) is simply not an audit event — not a parse failure.
                    continue
                }
                events.append(event)
            }
        }

        // Many Hermes sessions record no cwd. Fall back to the folder of the
        // first file the session touched, so those sessions still group under a
        // project instead of a bare "~".
        var projectBySession: [String: String] = [:]
        for event in events {
            guard projectBySession[event.sessionId] == nil, event.cwd == nil,
                  let path = event.paths.first, path.hasPrefix("/") else { continue }
            projectBySession[event.sessionId] = URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
        // Token counters for sessions that started since the last pass or wrote
        // something in it; the others have not changed.
        let tokenEvents = tokenCandidates.compactMap { id, event -> Event? in
            let started = sessions[id]?.started ?? .distantPast
            return started >= cutoff || activeSessions.contains(id) ? event : nil
        }.sorted { $0.id < $1.id }
        let resolved = (events + tokenEvents).map { event -> Event in
            guard event.cwd == nil, let cwd = projectBySession[event.sessionId] else { return event }
            return event.withCwd(cwd)
        }

        return ParseResult(events: resolved, skippedLines: 0, titles: collector.titles)
    }

    // MARK: - Helpers

    private static func event(
        call: [String: Any],
        id: String,
        ts: Date,
        sessionId: String,
        cwd: String?) -> Event?
    {
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
            rawJSON: nil)
    }

    private static func toolCalls(from text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = object as? [[String: Any]] {
            return array
        }
        if let wrapper = object as? [String: Any],
           let array = wrapper["tool_calls"] as? [[String: Any]]
        {
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
        row: (Row) -> Void) throws
    {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TranscriptError.unreadable(sqlite3_errmsg(handle).map { String(cString: $0) } ?? "sql")
        }
        defer { sqlite3_finalize(statement) }
        if sql.contains("?") {
            sqlite3_bind_double(statement, 1, (since ?? .distantPast).timeIntervalSince1970)
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            row(Row(statement: statement))
            status = sqlite3_step(statement)
        }
        // A busy or locked database ends the loop too; storing half a result as
        // if it were whole would hide the rest until the next change.
        guard status == SQLITE_DONE else {
            throw TranscriptError.unreadable(sqlite3_errmsg(handle).map { String(cString: $0) } ?? "step")
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
