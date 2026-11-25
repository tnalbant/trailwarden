// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation
import SQLite3

/// Cursor keeps its agent chats in the editor's global state database,
/// `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
/// table `cursorDiskKV(key, value)`, as JSON values under two key families:
///
/// - `composerData:<composerId>` — one chat: `createdAt`, `lastUpdatedAt`
///   (milliseconds), `name`, `modelConfig`
/// - `bubbleId:<composerId>:<bubbleId>[/…]` — one message or step: `type`
///   (1 user, 2 assistant), `text`, `createdAt` (ISO), `workspaceUris`, and for
///   a tool step `toolFormerData { name, status, params, rawArgs, result }`, where
///   `params` and `result` are JSON strings of their own.
///
/// Only those two key families are read. The same file holds the editor's other
/// state (`ItemTable`, including sign-in data) and the agent's prompt blobs;
/// none of it is queried.
public struct CursorDatabaseParser: DatabaseAgentParser {
    public init() {}

    public var agent: Agent {
        .cursor
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    /// A chat keeps changing while its tools run; a pass re-reads this much
    /// before the newest stored event. Ids are stable, so rows are replaced.
    static let rereadWindow: TimeInterval = 6 * 3600

    public func parse(database url: URL, since: Date?) throws -> ParseResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ParseResult(events: [], skippedLines: 0)
        }
        var handle: OpaquePointer?
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
        guard try Self.hasTable(handle) else { return ParseResult(events: [], skippedLines: 0) }

        let cutoff = since.map { ($0.timeIntervalSince1970 - Self.rereadWindow) * 1000 } ?? 0
        var events: [Event] = []
        var skipped = 0
        var collector = TitleCollector()

        var composers: [(id: String, data: [String: Any])] = []
        try Self.rows(handle, prefix: "composerData:") { key, value in
            guard let data = value else { return }
            guard let object = Self.json(data) else {
                skipped += 1
                return
            }
            let id = String(key.dropFirst("composerData:".count))
            let updated = Self.number(object["lastUpdatedAt"]) ?? Self.number(object["createdAt"]) ?? 0
            if updated >= cutoff {
                composers.append((id, object))
            }
        }

        for composer in composers {
            var bubbles: [(key: String, data: [String: Any])] = []
            try Self.rows(handle, prefix: "bubbleId:\(composer.id):") { key, value in
                guard let data = value else { return }
                guard let object = Self.json(data) else {
                    skipped += 1
                    return
                }
                bubbles.append((String(key.dropFirst("bubbleId:\(composer.id):".count)), object))
            }
            events.append(contentsOf: Self.events(
                composerID: composer.id,
                composer: composer.data,
                bubbles: bubbles,
                cutoffMillis: cutoff))
            let asked = bubbles.map { (millis: Self.millis(of: $0.data), key: $0.key, data: $0.data) }
                .filter { Int(saturating: Self.number($0.data["type"]) ?? 0) == 1 }
                .sorted { ($0.millis, $0.key) < ($1.millis, $1.key) }
            for bubble in asked {
                collector.firstMessage(bubble.data["text"] as? String, session: composer.id)
            }
        }
        return ParseResult(events: events, skippedLines: skipped, titles: collector.titles)
    }

    // MARK: - Mapping

    static func events(
        composerID: String,
        composer: [String: Any],
        bubbles: [(key: String, data: [String: Any])],
        cutoffMillis: Double) -> [Event]
    {
        typealias Bubble = (key: String, data: [String: Any], millis: Double)
        let timed: [Bubble] = bubbles.map { bubble -> Bubble in
            (key: bubble.key, data: bubble.data, millis: millis(of: bubble.data))
        }
        let ordered = timed.sorted { (lhs: Bubble, rhs: Bubble) -> Bool in
            if lhs.millis == rhs.millis {
                return lhs.key < rhs.key
            }
            return lhs.millis < rhs.millis
        }
        guard !ordered.isEmpty else { return [] }

        var cwd: String?
        var result: [Event] = []
        var inputTotal = 0.0, outputTotal = 0.0
        // Cursor names the model per reply, and only sometimes; the composer's
        // setting ("default" means Cursor picked) is the fallback.
        var lastModel = ((composer["modelConfig"] as? [String: Any])?["modelName"] as? String)
            .flatMap { $0 == "default" ? nil : $0 }

        func make(
            _ key: String,
            _ index: Int,
            _ kind: EventKind,
            millis: Double,
            tool: String? = nil,
            command: String? = nil,
            paths: [String] = [],
            preview: String?,
            raw: [String: Any]? = nil,
            usage: TokenCount? = nil) -> Event
        {
            Event(
                id: "cursor:\(composerID):\(key):\(index)",
                ts: Date(timeIntervalSince1970: millis / 1000),
                agent: .cursor,
                sessionId: composerID,
                kind: kind,
                cwd: cwd,
                tool: tool,
                command: command,
                paths: paths,
                preview: preview.map(CodexParser.cap),
                rawJSON: raw.flatMap(compactJSON),
                usage: usage)
        }

        if let created = number(composer["createdAt"]), created >= cutoffMillis {
            let name = composer["name"] as? String
            let model = (composer["modelConfig"] as? [String: Any])?["modelName"] as? String
            result.append(make(
                "start", 0, .sessionStart, millis: created,
                preview: [name, model.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")))
        }

        for bubble in ordered {
            let data = bubble.data
            if let uri = (data["workspaceUris"] as? [String])?.first, let path = URL(string: uri)?.path,
               !path.isEmpty
            {
                cwd = path
            }
            if let name = (data["modelInfo"] as? [String: Any])?["modelName"] as? String, !name.isEmpty {
                lastModel = name
            }
            if let tokens = data["tokenCount"] as? [String: Any] {
                inputTotal += number(tokens["inputTokens"]) ?? 0
                outputTotal += number(tokens["outputTokens"]) ?? 0
            }
            guard bubble.millis >= cutoffMillis else { continue }

            if let tool = data["toolFormerData"] as? [String: Any], let name = tool["name"] as? String {
                let params = jsonString(tool["params"]) ?? [:]
                let rawArgs = jsonString(tool["rawArgs"]) ?? [:]
                if let directory = params["cwd"] as? String, !directory.isEmpty {
                    cwd = directory
                }
                let call = toolCall(name: name, params: params, rawArgs: rawArgs)
                let status = tool["status"] as? String
                let raw: [String: Any] = [
                    "name": name, "status": status ?? "", "params": params, "rawArgs": rawArgs
                ]
                result.append(make(
                    bubble.key, 0, .toolCall, millis: bubble.millis, tool: name, command: call.command,
                    paths: call.paths, preview: call.preview, raw: raw))
                if let outcome = toolResult(tool["result"], status: status) {
                    result.append(make(
                        bubble.key, 1, .toolResult, millis: number(data["completedAtMs"]) ?? bubble.millis,
                        tool: name, preview: outcome))
                }
                continue
            }
            guard let text = data["text"] as? String, !text.isEmpty else { continue }
            let type = Int(saturating: number(data["type"]) ?? 0)
            guard type == 1 || type == 2 else { continue }
            result.append(make(
                bubble.key, 0, .message, millis: bubble.millis, preview: text,
                raw: ["type": type, "text": text]))
        }

        // Cursor reports no cache split, so its input is all fresh input.
        let usage = TokenCount(
            model: lastModel,
            input: Int(saturating: inputTotal),
            output: Int(saturating: outputTotal))
        if !usage.isEmpty, let last = ordered.last, last.millis >= cutoffMillis {
            result.append(make(
                "tokens", 0, .tokenUsage, millis: last.millis,
                preview: usage.preview, usage: usage))
        }
        return result
    }

    /// What a tool step did. Only the terminal tool gets a `command`; searches
    /// and web queries are previews, not commands that ran.
    static func toolCall(
        name: String,
        params: [String: Any],
        rawArgs: [String: Any]) -> (command: String?, paths: [String], preview: String?)
    {
        func first(_ keys: [String]) -> String? {
            for key in keys {
                if let value = params[key] as? String, !value.isEmpty {
                    return value
                }
                if let value = rawArgs[key] as? String, !value.isEmpty {
                    return value
                }
            }
            return nil
        }
        let path = first([
            "relativeWorkspacePath",
            "targetFile",
            "target_file",
            "path",
            "file_path",
            "filePath"
        ])

        switch name {
        case "run_terminal_command_v2", "run_terminal_cmd", "run_terminal_command":
            let command = first(["command"])
            return (command, [], command)
        case "glob_file_search", "file_search", "list_dir", "list_dir_v2":
            let directory = first(["targetDirectory", "target_directory", "directory", "path"])
            let pattern = first(["globPattern", "glob_pattern", "query"]) ?? ""
            return (
                nil,
                directory.map { [$0] } ?? [],
                [name, pattern, directory ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " "))
        case "grep", "grep_search", "ripgrep", "codebase_search", "web_search", "fetch_rules":
            let query = first(["pattern", "query", "searchTerm", "search_term"]) ?? ""
            return (nil, path.map { [$0] } ?? [], [name, query].filter { !$0.isEmpty }.joined(separator: " "))
        default:
            let detail = path ?? first(["toolName", "url", "query", "description"])
            return (nil, path.map { [$0] } ?? [], detail.map { "\(name) \($0)" } ?? name)
        }
    }

    /// `result` is a JSON string; the terminal puts its text in `output`.
    static func toolResult(_ value: Any?, status: String?) -> String? {
        let decoded = jsonString(value)
        let text = (decoded?["output"] as? String) ?? (decoded?["error"] as? String)
        if status == "error" {
            return "error: \(text ?? "")"
        }
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Values

    static func millis(of bubble: [String: Any]) -> Double {
        if let started = number(bubble["startedAtMs"]) {
            return started
        }
        if let text = bubble["createdAt"] as? String,
           let date = CodexParser.date(from: text, formatter: CodexParser.fractionalFormatter())
        {
            return date.timeIntervalSince1970 * 1000
        }
        return number(bubble["createdAt"]) ?? 0
    }

    static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func jsonString(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] {
            return object
        }
        guard let text = value as? String, let data = text.data(using: .utf8) else { return nil }
        return json(data)
    }

    static func compactJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - SQLite

    private static func hasTable(_ handle: OpaquePointer) throws -> Bool {
        var found = false
        try query(
            handle,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'cursorDiskKV'",
            [])
        { _ in
            found = true
        }
        return found
    }

    /// Keys from `prefix` up to the next prefix, through the key index; the
    /// table is never scanned whole.
    private static func rows(
        _ handle: OpaquePointer,
        prefix: String,
        _ body: (String, Data?) -> Void) throws
    {
        // Every prefix ends in ":"; ";" is the next character, so the range
        // holds exactly the keys that start with the prefix.
        let upper = String(prefix.dropLast()) + ";"
        try query(
            handle,
            "SELECT key, value FROM cursorDiskKV WHERE key >= ? AND key < ? ORDER BY key",
            [prefix, upper])
        { statement in
            guard let keyText = sqlite3_column_text(statement, 0) else { return }
            let key = String(cString: keyText)
            var value: Data?
            if sqlite3_column_type(statement, 1) != SQLITE_NULL, let bytes = sqlite3_column_blob(
                statement,
                1)
            {
                value = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            }
            body(key, value)
        }
    }

    private static func query(
        _ handle: OpaquePointer,
        _ sql: String,
        _ bindings: [String],
        row: (OpaquePointer) -> Void) throws
    {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TranscriptError.unreadable(sqlite3_errmsg(handle).map { String(cString: $0) } ?? "sql")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            row(statement)
            status = sqlite3_step(statement)
        }
        // A busy database also ends the loop; half a result is not a result.
        guard status == SQLITE_DONE else {
            throw TranscriptError.unreadable(sqlite3_errmsg(handle).map { String(cString: $0) } ?? "step")
        }
    }
}
