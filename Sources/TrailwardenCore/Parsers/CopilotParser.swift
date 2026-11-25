// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// Parser for GitHub Copilot's agent sessions — the Copilot CLI and the Copilot
/// desktop app share the format: `~/.copilot/session-state/<session>/events.jsonl`,
/// next to a `workspace.yaml` that names the folder.
///
/// Every line is `{ type, data, id, timestamp, parentId }`:
///
/// - `session.start` — `data.context.cwd`, `branch`, `copilotVersion`
/// - `user.message` / `assistant.message` — `data.content`; the assistant may add
///   `reasoningText`
/// - `tool.execution_start` — `toolName` and `arguments` (`bash` → `command`;
///   `create`, `edit`, `view` → `path`; `rg`, `glob` → `pattern`, `paths`)
/// - `tool.execution_complete` — `success`, `result.content`, `fileEdits[].path`
/// - `session.usage_record` — `usage.inputTokens` / `outputTokens` per call
/// - `permission.requested` — what the agent asked to be allowed to do
///
/// Hooks, model routing, checkpoints and turn markers carry nothing for the
/// audit trail and are passed over without counting as unknown.
public struct CopilotParser: AgentParser {
    public let agent: Agent = .copilot

    public init() {}

    public func accepts(_ url: URL) -> Bool {
        url.lastPathComponent == "events.jsonl"
    }

    static let ignoredTypes: Set<String> = [
        "hook.start", "hook.end", "session.warning", "session.info", "session.permissions_changed",
        "session.model_change", "session.auto_mode_resolved", "session.usage_checkpoint",
        "session.shutdown", "session.resume", "session.compaction_start", "session.compaction_complete",
        "system.message", "assistant.turn_start", "assistant.turn_end", "assistant.intent",
        "external_tool.requested", "external_tool.completed", "permission.completed", "abort"
    ]

    // One case per event type the format defines.
    // swiftlint:disable:next cyclomatic_complexity
    public func parse(file: URL) throws -> ParseResult {
        var events: [Event] = []
        var skippedLines = 0
        let sessionId = file.deletingLastPathComponent().lastPathComponent
        var cwd: String?
        var gitBranch: String?
        var toolNames: [String: String] = [:]
        var collector = TitleCollector()
        let source = file.path
        let formatter = CodexParser.fractionalFormatter()
        var lastTimestamp = CodexParser.modificationDate(of: file) ?? Date(timeIntervalSince1970: 0)

        try JSONLReader.forEachLine(at: file) { lineNumber, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = object["type"] as? String
            else {
                skippedLines += 1
                return
            }
            if let timestamp = CodexParser.date(from: object["timestamp"], formatter: formatter) {
                lastTimestamp = timestamp
            }
            let payload = object["data"] as? [String: Any] ?? [:]
            var index = 0

            func add(
                _ kind: EventKind,
                tool: String? = nil,
                command: String? = nil,
                paths: [String] = [],
                preview: String?,
                usage: TokenCount? = nil)
            {
                index += 1
                events.append(Event(
                    id: Event.makeID(
                        agent: .copilot,
                        sessionId: sessionId,
                        source: source,
                        line: lineNumber,
                        index: index),
                    ts: lastTimestamp,
                    agent: .copilot,
                    sessionId: sessionId,
                    kind: kind,
                    cwd: cwd,
                    gitBranch: gitBranch,
                    tool: tool,
                    command: command,
                    paths: paths,
                    preview: preview.map(CodexParser.cap),
                    rawJSON: line,
                    usage: usage))
            }

            switch type {
            case "session.start":
                let context = payload["context"] as? [String: Any] ?? [:]
                cwd = (context["cwd"] as? String) ?? cwd
                gitBranch = (context["branch"] as? String) ?? gitBranch
                let version = payload["copilotVersion"] as? String
                add(.sessionStart, preview: ["copilot", version].compactMap(\.self).joined(separator: " "))
            case "user.message":
                if let text = payload["content"] as? String, !text.isEmpty {
                    collector.firstMessage(text, session: sessionId)
                    add(.message, preview: text)
                }
            case "assistant.message":
                if let reasoning = payload["reasoningText"] as? String, !reasoning.isEmpty {
                    add(.reasoning, preview: reasoning)
                }
                if let text = payload["content"] as? String, !text.isEmpty {
                    add(.message, preview: text)
                }
            case "tool.execution_start":
                guard let name = payload["toolName"] as? String else {
                    skippedLines += 1
                    return
                }
                if let callID = payload["toolCallId"] as? String {
                    toolNames[callID] = name
                }
                let call = Self.toolCall(
                    name: name,
                    arguments: payload["arguments"] as? [String: Any] ?? [:],
                    title: payload["toolTitle"] as? String)
                add(.toolCall, tool: name, command: call.command, paths: call.paths, preview: call.preview)
            case "tool.execution_complete":
                let name = (payload["toolCallId"] as? String).flatMap { toolNames[$0] }
                let edits = (payload["fileEdits"] as? [[String: Any]] ?? [])
                    .compactMap { $0["path"] as? String }
                let content = (payload["result"] as? [String: Any])?["content"] as? String
                let failed = (payload["success"] as? Bool) == false
                let preview = failed ? "error: \(content ?? "")" : content
                add(.toolResult, tool: name, paths: edits, preview: preview)
            case "session.usage_record":
                let usage = payload["usage"] as? [String: Any] ?? [:]
                let count = Self.count(usage)
                if !count.isEmpty {
                    add(.tokenUsage, preview: count.preview, usage: count)
                }
            case "permission.requested":
                let request = payload["permissionRequest"] as? [String: Any] ?? [:]
                let summary = [request["kind"] as? String, request["toolName"] as? String]
                    .compactMap(\.self).joined(separator: " ")
                add(.permission, preview: summary.isEmpty ? "permission requested" : summary)
            default:
                if !Self.ignoredTypes.contains(type) {
                    skippedLines += 1
                }
            }
        }
        return ParseResult(events: events, skippedLines: skippedLines, titles: collector.titles)
    }

    /// `inputTokens` includes the cache reads and writes; `reasoningTokens` is
    /// part of `outputTokens`.
    static func count(_ usage: [String: Any]) -> TokenCount {
        TokenCount.includingCache(
            model: usage["model"] as? String ?? usage["responseModel"] as? String,
            input: TokenCount.number(usage["inputTokens"]),
            cached: TokenCount.number(usage["cacheReadTokens"]),
            cacheWrite: TokenCount.number(usage["cacheWriteTokens"]),
            output: TokenCount.number(usage["outputTokens"]),
            reasoning: TokenCount.number(usage["reasoningTokens"]))
    }

    /// What a tool call did. Only `bash` gets a `command`: a search pattern is
    /// not something that ran, and shell rules must not read it as one. File
    /// contents (`file_text`, `new_str`) stay out of the preview; the raw line
    /// keeps them, masked.
    static func toolCall(
        name: String,
        arguments: [String: Any],
        title: String?) -> (command: String?, paths: [String], preview: String?)
    {
        let path = (arguments["path"] as? String) ?? (arguments["file_path"] as? String)
        switch name {
        case "bash", "shell", "powershell":
            let command = arguments["command"] as? String
            return (command, [], command)
        case "create", "edit", "view", "str_replace", "str_replace_editor", "write", "read":
            return (nil, path.map { [$0] } ?? [], path)
        case "rg", "grep", "glob":
            var paths: [String] = []
            if let list = arguments["paths"] as? [String] {
                paths = list
            } else if let single = (arguments["paths"] as? String) ?? path {
                paths = [single]
            }
            let pattern = arguments["pattern"] as? String ?? ""
            return (nil, paths, ([name, pattern] + paths).filter { !$0.isEmpty }.joined(separator: " "))
        default:
            let detail = path ?? (arguments["url"] as? String) ?? (arguments["query"] as? String) ?? title
            return (nil, path.map { [$0] } ?? [], detail.map { "\(name) \($0)" } ?? name)
        }
    }
}
