// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import SQLite3

/// opencode keeps its history in `~/.local/share/opencode/opencode.db`:
///
/// - `session_v2(id, directory, title, time_created, tokens_input, tokens_output, …)`
/// - `session_message(id, session_id, type, seq, time_created, time_updated, data)`
///
/// `data` is JSON. A `user` message carries `text`; an `assistant` message
/// carries `content`, a list of parts — `text`, `reasoning`, and `tool` parts
/// with `name` and `state.input` (`command`/`workdir` for the shell, `path` or
/// `file_path` for reads and edits). Times are milliseconds since 1970.
///
/// Only the tables needed for the audit trail are read; `credential`, `account`
/// and the rest are never touched.
public struct OpencodeDatabaseParser: DatabaseAgentParser {
    public init() {}

    public var agent: Agent {
        .opencode
    }

    /// `$XDG_DATA_HOME/opencode/opencode.db`, else `~/.local/share/opencode/opencode.db`.
    public static var defaultURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                ".local/share",
                isDirectory: true)
        return base.appendingPathComponent("opencode/opencode.db")
    }

    /// An assistant message is written once and then updated while its tools
    /// run, so a pass re-reads a window before the newest stored event. Event ids
    /// are stable, so re-reading replaces rows instead of adding them.
    static let rereadWindow: TimeInterval = 6 * 3600
    private static let previewLimit = 500

    public func parse(database url: URL, since: Date?) throws -> ParseResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ParseResult(events: [], skippedLines: 0)
        }
        var handle: OpaquePointer?
        // Read-only snapshot; opencode keeps writing (WAL) while it runs.
        guard sqlite3_open_v2(
            "file:\(url.path)?mode=ro",
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil)
            == SQLITE_OK, let handle
        else {
            throw TranscriptError.unreadable(url.lastPathComponent)
        }
        defer { sqlite3_close(handle) }

        let cutoffMillis = since.map { ($0.timeIntervalSince1970 - Self.rereadWindow) * 1000 } ?? 0
        var sessions: [String: String] = [:]
        var events: [Event] = []
        var skipped = 0

        // Token columns came in over several releases; a missing one reads as 0.
        var columns = Set<String>()
        try Self.query(handle, "PRAGMA table_info(session_v2)") { row in
            if let name = row.text(1) {
                columns.insert(name)
            }
        }
        func column(_ name: String) -> String {
            columns.contains(name) ? name : "NULL"
        }
        try Self.query(
            handle,
            """
            SELECT id, directory, time_created, \(column("tokens_input")), \(column("tokens_output")),
                   \(column("tokens_cache_read")), time_updated, \(column("tokens_cache_write")),
                   \(column("tokens_reasoning")), \(column("model"))
            FROM session_v2
            """) { row in
                guard let id = row.text(0) else { return }
                let directory = row.text(1)
                sessions[id] = directory
                let created = Date(timeIntervalSince1970: row.double(2) / 1000)
                // Opencode keeps reasoning apart from output and bills it as output.
                let reasoning = Int(saturating: row.double(8))
                let usage = TokenCount(
                    model: Self.modelName(row.text(9)),
                    input: Int(saturating: row.double(3)),
                    output: Int(saturating: row.double(4)) + reasoning,
                    cacheRead: Int(saturating: row.double(5)),
                    cacheWrite: Int(saturating: row.double(7)),
                    reasoning: reasoning)
                // A long session keeps adding tokens: refresh it while it is still updated.
                guard row.double(6) >= cutoffMillis, !usage.isEmpty else { return }
                events.append(Event(
                    id: "opencode:\(id):tokens",
                    ts: created,
                    agent: .opencode,
                    sessionId: id,
                    kind: .tokenUsage,
                    cwd: directory,
                    preview: usage.preview,
                    usage: usage))
            }

        try Self.query(
            handle,
            """
            SELECT id, session_id, type, time_created, data FROM session_message
            WHERE time_created >= ? AND type IN ('user', 'assistant')
            ORDER BY time_created, seq
            """,
            bind: cutoffMillis)
        { row in
            guard let messageID = row.text(0), let sessionID = row.text(1), let type = row.text(2),
                  let json = row.text(4)
            else { return }
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                skipped += 1
                return
            }
            let ts = Date(timeIntervalSince1970: row.double(3) / 1000)
            events.append(contentsOf: Self.events(
                messageID: messageID,
                sessionID: sessionID,
                type: type,
                ts: ts,
                cwd: sessions[sessionID],
                data: object))
        }
        return ParseResult(events: events, skippedLines: skipped)
    }

    // MARK: - Mapping

    static func events(
        messageID: String,
        sessionID: String,
        type: String,
        ts: Date,
        cwd: String?,
        data: [String: Any]) -> [Event]
    {
        func make(
            _ index: Int,
            _ kind: EventKind,
            tool: String? = nil,
            command: String? = nil,
            paths: [String] = [],
            preview: String?,
            at time: Date = ts) -> Event
        {
            Event(
                id: "opencode:\(messageID):\(index)",
                ts: time,
                agent: .opencode,
                sessionId: sessionID,
                kind: kind,
                cwd: cwd,
                tool: tool,
                command: command,
                paths: paths,
                preview: preview.map { String($0.prefix(previewLimit)) })
        }

        if type == "user" {
            guard let text = data["text"] as? String, !text.isEmpty else { return [] }
            return [make(0, .message, preview: text)]
        }

        var result: [Event] = []
        let parts = data["content"] as? [[String: Any]] ?? []
        for (index, part) in parts.enumerated() {
            let partTime = (part["time"] as? [String: Any])?["start"] as? Double
            let time = partTime.map { Date(timeIntervalSince1970: $0 / 1000) } ?? ts
            switch part["type"] as? String {
            case "text":
                if let text = part["text"] as? String, !text.isEmpty {
                    result.append(make(index, .message, preview: text, at: time))
                }
            case "tool":
                guard let name = part["name"] as? String else { continue }
                let input = (part["state"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
                let call = toolCall(name: name, input: input)
                result.append(make(
                    index, .toolCall, tool: name, command: call.command, paths: call.paths,
                    preview: call.preview, at: time))
            default:
                continue
            }
        }
        return result
    }

    /// What a tool call did, in the event's terms. Only the shell gets a
    /// `command`: a grep pattern or a web query is not something that ran, and
    /// rules written for shell commands must not read it as one.
    static func toolCall(
        name: String,
        input: [String: Any]) -> (command: String?, paths: [String], preview: String?)
    {
        let path = (input["file_path"] as? String) ?? (input["path"] as? String)
        switch name {
        case "shell", "bash":
            let command = input["command"] as? String
            return (command, [], command)
        case "read", "write", "edit":
            return (nil, path.map { [$0] } ?? [], path)
        case "grep", "glob":
            let pattern = input["pattern"] as? String ?? ""
            return (
                nil,
                path.map { [$0] } ?? [],
                [name, pattern, path ?? ""].filter { !$0.isEmpty }
                    .joined(separator: " "))
        case "webfetch":
            return (nil, [], input["url"] as? String)
        case "websearch":
            return (nil, [], input["query"] as? String)
        case "execute":
            let code = input["code"] as? String
            return (nil, [], code)
        case "subagent":
            return (nil, [], (input["description"] as? String) ?? (input["prompt"] as? String))
        default:
            return (nil, path.map { [$0] } ?? [], path ?? input["description"] as? String)
        }
    }

    // MARK: - SQLite

    /// The model column is JSON (`{"id": …, "providerID": …}`) in current
    /// releases and a plain id in older ones.
    static func modelName(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return object["id"] as? String ?? object["modelID"] as? String
        }
        return value
    }

    private static func query(
        _ handle: OpaquePointer,
        _ sql: String,
        bind value: Double? = nil,
        row: (Row) -> Void) throws
    {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TranscriptError.unreadable(sqlite3_errmsg(handle).map { String(cString: $0) } ?? "sql")
        }
        defer { sqlite3_finalize(statement) }
        if let value {
            sqlite3_bind_double(statement, 1, value)
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            row(Row(statement: statement))
            status = sqlite3_step(statement)
        }
        // A busy database also ends the loop; half a result is not a result.
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
