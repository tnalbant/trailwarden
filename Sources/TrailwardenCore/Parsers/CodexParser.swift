// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Parser for Codex CLI rollout files
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<uuid>.jsonl`).
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

    public func parse(file: URL) throws -> ParseResult {
        var events: [Event] = []
        var skippedLines = 0
        var sessionId = Self.sessionID(from: file)
        var cwd: String?
        var gitBranch: String?
        var lastTimestamp: Date?
        var toolNamesByCallId: [String: String] = [:]
        var indexInLine = 0

        let source = file.path
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
            if let value = payload["cwd"] as? String { cwd = value }
            if let branch = Self.gitBranch(from: payload["git"]) { gitBranch = branch }

            let timestamp = lastTimestamp ?? fallbackTimestamp

            func add(
                _ kind: EventKind,
                tool: String? = nil,
                command: String? = nil,
                paths: [String] = [],
                preview: String? = nil
            ) {
                indexInLine += 1
                events.append(
                    Event(
                        id: Event.makeID(
                            agent: agent,
                            sessionId: sessionId,
                            source: source,
                            line: lineNumber,
                            index: indexInLine
                        ),
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
                        rawJSON: line
                    )
                )
            }

            switch type {
            case "session_meta":
                if sessionId.isEmpty,
                   let id = payload["id"] as? String ?? payload["session_id"] as? String {
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
                    let input = Self.toolInput(payload["input"])
                    add(
                        .toolCall,
                        tool: name,
                        command: input.command,
                        paths: input.paths,
                        preview: input.preview
                    )

                case "custom_tool_call_output", "function_call_output":
                    let callId = payload["call_id"] as? String
                    add(
                        .toolResult,
                        tool: callId.flatMap { toolNamesByCallId[$0] },
                        preview: Self.text(from: payload["output"])
                    )

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
                        preview: input.preview
                    )

                default:
                    break
                }

            case "event_msg":
                if payloadType == "token_count" {
                    add(.tokenUsage, preview: Self.tokenUsagePreview(payload))
                }

            case "token_usage_record":
                add(.tokenUsage, preview: Self.tokenUsagePreview(payload))

            default:
                // turn_context / world_state / compacted carry no event of their own;
                // a turn_context can still update the working directory above.
                break
            }
        }

        return ParseResult(events: events, skippedLines: skippedLines)
    }

    // MARK: - Line vocabulary

    static let knownTypes: Set<String> = [
        "session_meta", "response_item", "event_msg",
        "token_usage_record", "turn_context", "world_state", "compacted",
    ]

    static let previewLimit = 500

    static func cap(_ text: String) -> String {
        String(text.prefix(previewLimit))
    }

    /// Text of a content/summary field: either a plain string or a list of
    /// blocks that each carry `text` (image blocks carry `image_url` instead).
    static func text(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
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
    static func toolInput(_ value: Any?) -> (command: String?, paths: [String], preview: String?) {
        if let string = value as? String, !string.isEmpty {
            return (string, [], string)
        }
        guard let dict = value as? [String: Any] else { return (nil, [], nil) }

        var command: String?
        if let string = dict["command"] as? String {
            command = string
        } else if let parts = dict["command"] as? [String], !parts.isEmpty {
            command = parts.joined(separator: " ")
        } else if let string = dict["cmd"] as? String {
            command = string
        }

        var paths: [String] = []
        for key in ["file_path", "path"] {
            if let path = dict[key] as? String { paths.append(path) }
        }
        if let files = dict["files"] as? [String] { paths.append(contentsOf: files) }

        let preview = (dict["description"] as? String)
            ?? (dict["title"] as? String)
            ?? command
        return (command, paths, preview)
    }

    static func arguments(_ value: Any?) -> [String: Any]? {
        guard
            let string = value as? String,
            let data = string.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object as? [String: Any]
    }

    /// Two shapes exist: `event_msg`/`token_count` carries cumulative
    /// `info.total_token_usage`, while `token_usage_record` carries a per-response
    /// `usage` block.
    static func tokenUsagePreview(_ payload: [String: Any]) -> String? {
        if let info = payload["info"] as? [String: Any] {
            if let total = info["total_token_usage"] as? [String: Any],
               let tokens = total["total_tokens"] as? Int {
                return "total tokens: \(tokens)"
            }
            return "token usage"
        }
        if let usage = payload["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int
            let output = usage["output_tokens"] as? Int
            switch (input, output) {
            case let (input?, output?): return "tokens: \(input) in / \(output) out"
            case let (input?, nil): return "tokens: \(input) in"
            case let (nil, output?): return "tokens: \(output) out"
            default: break
            }
        }
        if let total = payload["total_tokens"] as? Int {
            return "tokens: \(total)"
        }
        return "token usage"
    }

    // MARK: - Session identity

    /// `rollout-<timestamp>-<uuid>.jsonl` -> `<uuid>`; anything else keeps the
    /// file stem so two sessions never collide.
    static func sessionID(from file: URL) -> String {
        let stem = file.deletingPathExtension().lastPathComponent
        guard let uuid = uuidSuffix(of: stem) else { return stem }
        return uuid
    }

    static func uuidSuffix(of stem: String) -> String? {
        guard stem.count >= 36 else { return nil }
        let candidate = String(stem.suffix(36))
        let parts = candidate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5, parts.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard candidate.replacingOccurrences(of: "-", with: "").unicodeScalars.allSatisfy(hexDigits.contains) else {
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
        if let date = formatter.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func gitBranch(from value: Any?) -> String? {
        if let branch = value as? String, !branch.isEmpty { return branch }
        if let dict = value as? [String: Any] {
            for key in ["branch", "current_branch", "name"] {
                if let branch = dict[key] as? String, !branch.isEmpty { return branch }
            }
        }
        return nil
    }
}
