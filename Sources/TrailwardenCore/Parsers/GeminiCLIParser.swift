// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Gemini CLI keeps one JSON document per session under
/// `~/.gemini/tmp/<project>/chats/session-*.json`:
///
/// ```json
/// {"sessionId": "...", "startTime": "...", "messages": [
///   {"id": "...", "timestamp": "...", "type": "user|gemini|info",
///    "content": "…", "toolCalls": [{"name": "run_shell_command",
///    "args": {"command": "brew upgrade gemini-cli"}, "result": [...]}]}]}
/// ```
///
/// A tool call is the interesting part — that is where shell commands and file
/// writes show up — so those become `.toolCall` events and the prose becomes
/// `.message` events. `info` messages are CLI notices, not work, and are dropped.
public struct GeminiCLIParser: AgentParser {
    public init() {}

    public var agent: Agent {
        .gemini
    }

    public var fileExtension: String {
        "json"
    }

    /// Canonical tool names, so a rule written for `Bash` also covers Gemini.
    private static let toolAliases: [String: String] = [
        "run_shell_command": "Bash",
        "shell": "Bash",
        "read_file": "Read",
        "read_many_files": "Read",
        "write_file": "Write",
        "replace": "Edit",
        "edit": "Edit",
        "list_directory": "Bash",
        "glob": "Bash",
        "grep_search": "Bash",
        "web_fetch": "WebFetch",
        "google_web_search": "WebSearch"
    ]

    private static let pathKeys = ["absolute_path", "file_path", "path", "target_file", "directory_path"]

    public func parse(file: URL) throws -> ParseResult {
        guard isTranscript(file) else { return ParseResult(events: [], skippedLines: 0) }

        let data = try Data(contentsOf: file)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A file named like a transcript that is not JSON is a real failure;
            // any other JSON under the tree is simply not ours.
            throw TranscriptError.unreadable(file.lastPathComponent)
        }
        guard let messages = root["messages"] as? [[String: Any]] else {
            return ParseResult(events: [], skippedLines: 0)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()

        let sessionId = root["sessionId"] as? String
            ?? file.deletingPathExtension().lastPathComponent
        let fallbackDate = (root["startTime"] as? String)
            .flatMap { formatter.date(from: $0) ?? plainFormatter.date(from: $0) }
            ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? Date(timeIntervalSince1970: 0)

        var events: [Event] = []
        var skipped = 0

        for (index, message) in messages.enumerated() {
            guard let messageId = message["id"] as? String ?? Optional("m\(index)") else { continue }
            let type = message["type"] as? String ?? ""
            let date = (message["timestamp"] as? String)
                .flatMap { formatter.date(from: $0) ?? plainFormatter.date(from: $0) }
                ?? fallbackDate

            switch type {
            case "info":
                continue
            case "user", "gemini":
                let text = Self.text(from: message["content"])
                if type == "user", let text, !text.isEmpty {
                    events.append(Event(
                        id: "gemini:\(sessionId):\(messageId):u",
                        ts: date,
                        agent: .gemini,
                        sessionId: sessionId,
                        kind: .message,
                        preview: text,
                        risk: [],
                        rawJSON: nil))
                }
                for (callIndex, call) in (message["toolCalls"] as? [[String: Any]] ?? []).enumerated() {
                    guard let event = Self.event(
                        call: call,
                        index: callIndex,
                        sessionId: sessionId,
                        messageId: messageId,
                        date: date)
                    else {
                        skipped += 1
                        continue
                    }
                    events.append(event)
                }
                // Gemini's own prose is assistant output; only keep it when it
                // carries no tool call, otherwise the timeline doubles up.
                if type == "gemini",
                   text != nil,
                   (message["toolCalls"] as? [[String: Any]] ?? []).isEmpty
                {
                    events.append(Event(
                        id: "gemini:\(sessionId):\(messageId):a",
                        ts: date,
                        agent: .gemini,
                        sessionId: sessionId,
                        kind: .message,
                        preview: text,
                        risk: [],
                        rawJSON: nil))
                }
            default:
                skipped += 1
            }
            if type == "gemini", let usage = Self.usage(message) {
                events.append(Event(
                    id: "gemini:\(sessionId):\(messageId):t",
                    ts: date,
                    agent: .gemini,
                    sessionId: sessionId,
                    kind: .tokenUsage,
                    preview: usage.preview,
                    risk: [],
                    rawJSON: nil,
                    usage: usage))
            }
        }

        return ParseResult(events: events, skippedLines: skipped)
    }

    // MARK: - Helpers

    /// `tokens: {input, output, cached, thoughts, tool, total}` per reply.
    /// `input` includes the cached part; `thoughts` is billed as output but
    /// not counted in `output` (total = input + output + thoughts).
    static func usage(_ message: [String: Any]) -> TokenCount? {
        guard let tokens = message["tokens"] as? [String: Any] else { return nil }
        let thoughts = TokenCount.number(tokens["thoughts"])
        let count = TokenCount.includingCache(
            model: message["model"] as? String,
            input: TokenCount.number(tokens["input"]),
            cached: TokenCount.number(tokens["cached"]),
            output: TokenCount.number(tokens["output"]) + thoughts,
            reasoning: thoughts)
        return count.isEmpty ? nil : count
    }

    private func isTranscript(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("session-") && url.pathExtension == "json"
    }

    private static func event(
        call: [String: Any],
        index: Int,
        sessionId: String,
        messageId: String,
        date: Date) -> Event?
    {
        guard let name = call["name"] as? String else { return nil }
        let args = call["args"] as? [String: Any] ?? [:]
        let paths = pathKeys.compactMap { args[$0] as? String }
        let command = (args["command"] as? String) ?? (args["cmd"] as? String)

        // A call with neither a command nor a path is noise for this product.
        guard command != nil || !paths.isEmpty else { return nil }

        return Event(
            id: "gemini:\(sessionId):\(messageId):\(index)",
            ts: date,
            agent: .gemini,
            sessionId: sessionId,
            kind: .toolCall,
            cwd: args["working_directory"] as? String ?? args["directory"] as? String,
            tool: toolAliases[name] ?? name,
            command: command,
            paths: paths,
            preview: command ?? paths.first,
            risk: [],
            rawJSON: nil)
    }

    static func text(from content: Any?) -> String? {
        if let text = content as? String {
            return text
        }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let parts = blocks.compactMap { $0["text"] as? String }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

public enum TranscriptError: Error, CustomStringConvertible, Sendable {
    case unreadable(String)

    public var description: String {
        switch self {
        case let .unreadable(name): "\(name) is not a readable transcript"
        }
    }
}
