// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Parser for Claude Code session transcripts
/// (`~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`).
///
/// Each line is one JSON object. The interesting parts are `message.content`
/// blocks (`text`, `thinking`, `tool_use`, `tool_result`) plus the top-level
/// `toolUseResult` that accompanies tool results. Unknown line types are
/// counted, never fatal: the format changes without notice.
public struct ClaudeCodeParser: AgentParser {
    public let agent: Agent = .claudeCode

    public init() {}

    // A switch over the transcript's event types: every case is one shape the
    // agent writes, and counting them as branches says nothing useful.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func parse(file: URL) throws -> ParseResult {
        var events: [Event] = []
        var skippedLines = 0
        var sessionId = ""
        var toolNamesByUseId: [String: String] = [:]
        var lastTimestamp: Date?
        var cwd: String?
        var gitBranch: String?
        var indexInLine = 0
        // One API response is written as several lines (one per content block),
        // each repeating the same usage; the last copy of each is kept.
        var usageByRequest: [String: PendingUsage] = [:]
        var requestOrder: [String] = []
        var collector = TitleCollector()
        // Title records often come before the first line that names the session.
        var agentTitle: (text: String, session: String?)?

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

            if let id = object["sessionId"] as? String ?? object["session_id"] as? String {
                sessionId = id
            }
            if let timestamp = Self.date(from: object["timestamp"], formatter: formatter) {
                lastTimestamp = timestamp
            }
            if let value = object["cwd"] as? String {
                cwd = value
            }
            if let value = object["gitBranch"] as? String {
                gitBranch = value
            }

            guard Self.knownTypes.contains(type) else {
                skippedLines += 1
                return
            }

            let timestamp = lastTimestamp ?? fallbackTimestamp

            func add(
                _ kind: EventKind,
                tool: String? = nil,
                command: String? = nil,
                paths: [String] = [],
                preview: String? = nil)
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
                        rawJSON: line))
            }

            switch type {
            case "user", "assistant":
                guard let message = object["message"] as? [String: Any] else { return }
                if type == "user", object["isMeta"] as? Bool != true {
                    collector.firstMessage(Self.userText(message["content"]), session: sessionId)
                }
                if type == "assistant", let usage = Self.usage(message),
                   let request = object["requestId"] as? String ?? message["id"] as? String
                {
                    if usageByRequest[request] == nil {
                        requestOrder.append(request)
                    }
                    usageByRequest[request] = PendingUsage(
                        usage: usage, line: lineNumber, ts: timestamp,
                        sessionId: sessionId, cwd: cwd, gitBranch: gitBranch)
                }
                if let text = message["content"] as? String {
                    add(.message, preview: text)
                } else if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks {
                        switch block["type"] as? String {
                        case "text":
                            add(.message, preview: block["text"] as? String)
                        case "thinking":
                            add(.reasoning, preview: block["thinking"] as? String)
                        case "tool_use":
                            let name = block["name"] as? String
                            if let useId = block["id"] as? String, let name {
                                toolNamesByUseId[useId] = name
                            }
                            let input = block["input"] as? [String: Any] ?? [:]
                            add(
                                .toolCall,
                                tool: name,
                                command: input["command"] as? String,
                                paths: Self.paths(in: input),
                                preview: Self.toolCallPreview(input))
                        case "tool_result":
                            let useId = block["tool_use_id"] as? String
                            let result = object["toolUseResult"] as? [String: Any] ?? [:]
                            let paths = (result["file"] as? String).map { [$0] } ?? []
                            add(
                                .toolResult,
                                tool: useId.flatMap { toolNamesByUseId[$0] },
                                paths: paths,
                                preview: Self.toolResultPreview(block: block, result: result))
                        default:
                            break
                        }
                    }
                }

            case "summary", "ai-title":
                let key = type == "summary" ? "summary" : "title"
                if let text = object[key] as? String ?? object["aiTitle"] as? String {
                    agentTitle = (text, object["sessionId"] as? String)
                }

            case "permission-mode":
                if let mode = object["permissionMode"] as? String {
                    add(.permission, preview: "permission mode: \(mode)")
                }

            case "mode":
                if let mode = object["mode"] as? String {
                    add(.permission, preview: "mode: \(mode)")
                }

            default:
                // Known but carries no event of its own: system metadata,
                // attachments, file-history snapshots, session title, last prompt.
                break
            }
        }

        events += requestOrder.compactMap { usageByRequest[$0] }.map { usageEvent($0, source: source) }
        if let agentTitle {
            collector.summary(agentTitle.text, session: agentTitle.session ?? sessionId)
        }
        return ParseResult(events: events, skippedLines: skippedLines, titles: collector.titles)
    }

    /// The typed text of a user line: a string, or its text blocks. Tool
    /// results are not something the user wrote.
    static func userText(_ content: Any?) -> String? {
        if let text = content as? String {
            return text
        }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let parts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func usageEvent(_ pending: PendingUsage, source: String) -> Event {
        Event(
            // Content blocks use small indexes; this one never collides.
            id: Event.makeID(
                agent: agent, sessionId: pending.sessionId, source: source,
                line: pending.line, index: Self.usageIndex),
            ts: pending.ts,
            agent: agent,
            sessionId: pending.sessionId,
            kind: .tokenUsage,
            cwd: pending.cwd,
            gitBranch: pending.gitBranch,
            preview: pending.usage.preview,
            usage: pending.usage)
    }

    private struct PendingUsage {
        let usage: TokenCount
        let line: Int
        let ts: Date
        let sessionId: String
        let cwd: String?
        let gitBranch: String?
    }

    static let usageIndex = 10000

    /// Anthropic usage: `input_tokens` is only the uncached part, cache reads
    /// and writes are their own fields, and thinking is inside `output_tokens`.
    static func usage(_ message: [String: Any]) -> TokenCount? {
        guard let usage = message["usage"] as? [String: Any] else { return nil }
        let model = (message["model"] as? String).flatMap { $0.hasPrefix("<") ? nil : $0 }
        let details = usage["output_tokens_details"] as? [String: Any]
        let count = TokenCount(
            model: model,
            input: TokenCount.number(usage["input_tokens"]),
            output: TokenCount.number(usage["output_tokens"]),
            cacheRead: TokenCount.number(usage["cache_read_input_tokens"]),
            cacheWrite: TokenCount.number(usage["cache_creation_input_tokens"]),
            reasoning: TokenCount.number(details?["thinking_tokens"]))
        return count.isEmpty ? nil : count
    }

    // MARK: - Line vocabulary

    static let knownTypes: Set<String> = [
        "user", "assistant", "system", "attachment",
        "file-history-snapshot", "mode", "permission-mode",
        "last-prompt", "ai-title", "summary"
    ]

    static let previewLimit = 500

    static func cap(_ text: String) -> String {
        String(text.prefix(previewLimit))
    }

    static func paths(in input: [String: Any]) -> [String] {
        ["file_path", "path", "notebook_path"].compactMap { input[$0] as? String }
    }

    static func toolCallPreview(_ input: [String: Any]) -> String? {
        if let description = input["description"] as? String, !description.isEmpty {
            return description
        }
        if let command = input["command"] as? String, !command.isEmpty {
            return command
        }
        for key in input.keys.sorted() {
            if let value = input[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func toolResultPreview(block: [String: Any], result: [String: Any]) -> String? {
        if let text = block["content"] as? String, !text.isEmpty {
            return text
        }
        if let items = block["content"] as? [[String: Any]] {
            let joined = items.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !joined.isEmpty {
                return joined
            }
        }
        if let stdout = result["stdout"] as? String, !stdout.isEmpty {
            return stdout
        }
        if let stderr = result["stderr"] as? String, !stderr.isEmpty {
            return stderr
        }
        return nil
    }

    // MARK: - Dates

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
        // Some entries drop the fractional seconds.
        return ISO8601DateFormatter().date(from: text)
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
