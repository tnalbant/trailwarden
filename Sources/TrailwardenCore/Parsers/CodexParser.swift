// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Parser for Codex CLI rollout files
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<uuid>.jsonl`). Codex later
/// compresses older rollouts to `….jsonl.zst`; those are read through the
/// vendored zstd decoder and give the same events, with the same ids.
///
/// Every line is `{ timestamp, ordinal, type, payload, metadata }`. The payload
/// carries the meaning: `message`, `reasoning`, `custom_tool_call`,
/// `custom_tool_call_output`, `function_call`, `function_call_output`,
/// `token_count`. `item_completed` duplicates calls that were already emitted,
/// and `developer` messages are boilerplate instructions, so neither produces an
/// event.
public struct CodexParser: AgentParser {
    public let agent: Agent = .codex

    public init() {}

    public func accepts(_ url: URL) -> Bool {
        url.pathExtension == "jsonl"
            || (url.pathExtension == "zst" && url.deletingPathExtension().pathExtension == "jsonl")
    }

    /// The plain `.jsonl` path a file stands for. Event ids are derived from it,
    /// so a rollout that Codex compresses after it was indexed keeps its ids and
    /// is not counted twice.
    static func logicalPath(of file: URL) -> String {
        file.pathExtension == "zst" ? file.deletingPathExtension().path : file.path
    }

    // A switch over the transcript's event types: every case is one shape the
    // agent writes, and counting them as branches says nothing useful.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func parse(file: URL) throws -> ParseResult {
        var events: [Event] = []
        var skippedLines = 0
        var sessionId = Self.sessionID(from: file)
        var cwd: String?
        var gitBranch: String?
        var lastTimestamp: Date?
        var toolNamesByCallId: [String: String] = [:]
        var indexInLine = 0
        var tokens = TokenTracker()
        var collector = TitleCollector()

        let source = Self.logicalPath(of: file)
        let fallbackTimestamp = Self.modificationDate(of: file) ?? Date(timeIntervalSince1970: 0)
        let formatter = Self.fractionalFormatter()

        try JSONLReader.forEachLine(at: file) { lineNumber, rawLine in
            indexInLine = 0
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }

            guard
                let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data),
                let object = json as? [String: Any],
                let type = object["type"] as? String
            else {
                skippedLines += 1
                return
            }

            if let timestamp = Self.date(from: object["timestamp"], formatter: formatter) {
                lastTimestamp = timestamp
            }

            guard Self.knownTypes.contains(type) else {
                skippedLines += 1
                return
            }

            let payload = object["payload"] as? [String: Any] ?? [:]
            let payloadType = payload["type"] as? String
            if let value = payload["cwd"] as? String {
                cwd = value
            }
            if let branch = Self.gitBranch(from: payload["git"]) {
                gitBranch = branch
            }

            let timestamp = lastTimestamp ?? fallbackTimestamp

            func add(
                _ kind: EventKind,
                tool: String? = nil,
                command: String? = nil,
                paths: [String] = [],
                preview: String? = nil,
                usage: TokenCount? = nil)
            {
                indexInLine += 1
                events.append(
                    Event(
                        id: Event.makeID(
                            agent: agent,
                            sessionId: sessionId,
                            source: source,
                            line: lineNumber,
                            index: indexInLine),
                        ts: timestamp,
                        agent: agent,
                        sessionId: sessionId,
                        kind: kind,
                        cwd: cwd,
                        gitBranch: gitBranch,
                        tool: tool,
                        command: command,
                        paths: paths,
                        preview: preview.map(Self.cap),
                        risk: [],
                        rawJSON: line,
                        usage: usage))
            }

            switch type {
            case "session_meta":
                if sessionId.isEmpty,
                   let id = payload["id"] as? String ?? payload["session_id"] as? String
                {
                    sessionId = id
                }
                add(.sessionStart, preview: "session start")

            case "response_item":
                switch payloadType {
                case "message":
                    // "developer" messages are the agent's standing instructions,
                    // not part of the session's story.
                    let role = payload["role"] as? String ?? "assistant"
                    if role != "developer", let text = Self.text(from: payload["content"]) {
                        if role == "user" {
                            collector.firstMessage(text, session: sessionId)
                        }
                        add(.message, preview: text)
                    }

                case "reasoning":
                    if let text = Self.text(from: payload["summary"]) {
                        add(.reasoning, preview: text)
                    }

                case "custom_tool_call":
                    let name = payload["name"] as? String
                    if let callId = payload["call_id"] as? String, let name {
                        toolNamesByCallId[callId] = name
                    }
                    let input = Self.codeModeInput(payload["input"]) ?? Self.toolInput(payload["input"])
                    add(
                        .toolCall,
                        tool: input.tool ?? name,
                        command: input.command,
                        paths: input.paths,
                        preview: input.preview)

                case "custom_tool_call_output", "function_call_output":
                    let callId = payload["call_id"] as? String
                    add(
                        .toolResult,
                        tool: callId.flatMap { toolNamesByCallId[$0] },
                        preview: Self.text(from: payload["output"]))

                case "function_call":
                    let name = payload["name"] as? String
                    if let callId = payload["call_id"] as? String, let name {
                        toolNamesByCallId[callId] = name
                    }
                    let input = Self.toolInput(Self.arguments(payload["arguments"]))
                    add(
                        .toolCall,
                        tool: name,
                        command: input.command,
                        paths: input.paths,
                        preview: input.preview)

                default:
                    break
                }

            case "turn_context", "event_msg", "token_usage_record":
                if let count = tokens.handle(type, payload) {
                    add(.tokenUsage, preview: count.preview, usage: count)
                    if type == "token_usage_record", let id = events.last?.id {
                        tokens.recordIDs.insert(id)
                    }
                }

            default:
                // world_state / compacted carry no event of their own.
                break
            }
        }

        // A rollout that has running totals also has per-response records for
        // the same calls; counting both would double the session.
        if tokens.sawRunningTotal, !tokens.recordIDs.isEmpty {
            events.removeAll { tokens.recordIDs.contains($0.id) }
        }
        return ParseResult(events: events, skippedLines: skippedLines, titles: collector.titles)
    }

    /// What a rollout has said about tokens so far.
    struct TokenTracker {
        var model: String?
        var previousTotal: TokenCount?
        var sawRunningTotal = false
        var recordIDs: Set<String> = []

        /// The tokens a line adds, if any; a `turn_context` only names the model.
        mutating func handle(_ type: String, _ payload: [String: Any]) -> TokenCount? {
            switch type {
            case "turn_context":
                model = payload["model"] as? String ?? model
                return nil
            case "event_msg" where payload["type"] as? String == "token_count":
                return runningTotal(payload)
            case "token_usage_record":
                return record(payload)
            default:
                return nil
            }
        }

        /// The running total is the one number Codex never repeats out of step:
        /// `last_token_usage` comes twice when a turn is re-reported, the
        /// difference between two totals does not.
        mutating func runningTotal(_ payload: [String: Any]) -> TokenCount? {
            guard let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any] else { return nil }
            let total = CodexParser.count(usage, model: model)
            let delta = previousTotal.map { total.since($0) } ?? total
            previousTotal = total
            sawRunningTotal = sawRunningTotal || !total.isEmpty
            return delta.isEmpty ? nil : delta
        }

        func record(_ payload: [String: Any]) -> TokenCount? {
            guard let usage = payload["usage"] as? [String: Any] else { return nil }
            let count = CodexParser.count(usage, model: payload["model"] as? String ?? model)
            return count.isEmpty ? nil : count
        }
    }

    /// An OpenAI usage block, normalized so cached tokens are not also input.
    static func count(_ usage: [String: Any], model: String?) -> TokenCount {
        TokenCount.includingCache(
            model: model,
            input: TokenCount.number(usage["input_tokens"]),
            cached: TokenCount.number(usage["cached_input_tokens"]),
            cacheWrite: TokenCount.number(usage["cache_write_input_tokens"]),
            output: TokenCount.number(usage["output_tokens"]),
            reasoning: TokenCount.number(usage["reasoning_output_tokens"]))
    }

    // MARK: - Line vocabulary

    static let knownTypes: Set<String> = [
        "session_meta", "response_item", "event_msg",
        "token_usage_record", "turn_context", "world_state", "compacted"
    ]

    static let previewLimit = 500

    static func cap(_ text: String) -> String {
        String(text.prefix(previewLimit))
    }

    /// Text of a content/summary field: either a plain string or a list of
    /// blocks that each carry `text` (image blocks carry `image_url` instead).
    static func text(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let blocks = value as? [[String: Any]] {
            let joined = blocks
                .compactMap { $0["text"] as? String }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// `custom_tool_call.input` is a raw string for the `exec` tool and an object
    /// for others; `function_call.arguments` is a JSON string that was already
    /// decoded by the caller.
    typealias ToolInput = (tool: String?, command: String?, paths: [String], preview: String?)

    /// A code-mode program, recorded as what it runs rather than as JavaScript.
    /// A patch keeps its source as the command: the detail view draws the diff
    /// from it.
    static func codeModeInput(_ value: Any?) -> ToolInput? {
        guard let source = value as? String, let program = CodexCodeMode.read(source) else { return nil }
        guard !program.commands.isEmpty else {
            return (program.displayTool, source, program.patchedPaths, source)
        }
        let commands = program.commands.joined(separator: "\n")
        return (program.displayTool, commands, program.patchedPaths, commands)
    }

    static func toolInput(_ value: Any?) -> ToolInput {
        if let string = value as? String, !string.isEmpty {
            return (nil, string, [], string)
        }
        guard let dict = value as? [String: Any] else { return (nil, nil, [], nil) }

        var command: String?
        if let string = dict["command"] as? String {
            command = string
        } else if let parts = dict["command"] as? [String], !parts.isEmpty {
            command = shellScript(parts) ?? parts.joined(separator: " ")
        } else if let string = dict["cmd"] as? String {
            command = string
        }

        var paths: [String] = []
        for key in ["file_path", "path"] {
            if let path = dict[key] as? String {
                paths.append(path)
            }
        }
        if let files = dict["files"] as? [String] {
            paths.append(contentsOf: files)
        }

        let preview = (dict["description"] as? String)
            ?? (dict["title"] as? String)
            ?? command
        return (nil, command, paths, preview)
    }

    /// `["bash", "-lc", "rm -rf ~"]` runs the script `rm -rf ~`, and that script
    /// is the command: joined with spaces it would read `bash -lc rm -rf ~`, and
    /// rules that look for a command's start would miss its first command.
    static func shellScript(_ parts: [String]) -> String? {
        guard parts.count == 3,
              ["sh", "bash", "zsh"].contains((parts[0] as NSString).lastPathComponent),
              ["-c", "-lc"].contains(parts[1])
        else { return nil }
        return parts[2]
    }

    static func arguments(_ value: Any?) -> [String: Any]? {
        guard
            let string = value as? String,
            let data = string.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object as? [String: Any]
    }

    // MARK: - Session identity

    /// `rollout-<timestamp>-<uuid>.jsonl` -> `<uuid>`; anything else keeps the
    /// file stem so two sessions never collide.
    static func sessionID(from file: URL) -> String {
        let stem = URL(fileURLWithPath: logicalPath(of: file)).deletingPathExtension().lastPathComponent
        guard let uuid = uuidSuffix(of: stem) else { return stem }
        return uuid
    }

    static func uuidSuffix(of stem: String) -> String? {
        guard stem.count >= 36 else { return nil }
        let candidate = String(stem.suffix(36))
        let parts = candidate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5, parts.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard candidate.replacingOccurrences(of: "-", with: "").unicodeScalars.allSatisfy(hexDigits.contains)
        else {
            return nil
        }
        return candidate.lowercased()
    }

    // MARK: - Dates and branches

    static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func date(from value: Any?, formatter: ISO8601DateFormatter) -> Date? {
        guard let text = value as? String else { return nil }
        if let date = formatter.date(from: text) {
            return date
        }
        return ISO8601DateFormatter().date(from: text)
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func gitBranch(from value: Any?) -> String? {
        if let branch = value as? String, !branch.isEmpty {
            return branch
        }
        if let dict = value as? [String: Any] {
            for key in ["branch", "current_branch", "name"] {
                if let branch = dict[key] as? String, !branch.isEmpty {
                    return branch
                }
            }
        }
        return nil
    }
}
