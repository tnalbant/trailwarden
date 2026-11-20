// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// A small Model Context Protocol server over stdio, so another agent can ask
/// Trailwarden "what happened here" instead of reading raw transcripts.
///
/// The router is pure — text in, text out — which is what makes it testable
/// without spawning a process. `main.swift` only moves bytes.
public struct MCPRouter: @unchecked Sendable {
    public static let protocolVersion = "2025-06-18"
    private let store: EventStore

    public init(store: EventStore) {
        self.store = store
    }

    /// Returns `nil` for notifications, which take no response.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Self.error(id: nil, code: -32700, message: "parse error")
        }

        let id = request["id"]
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]

        if id == nil, method.hasPrefix("notifications/") {
            return nil
        }

        switch method {
        case "initialize":
            return Self.result(id, [
                "protocolVersion": Self.protocolVersion,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "trailwarden", "version": TrailwardenVersion.current]
            ])
        case "ping":
            return Self.result(id, [:])
        case "tools/list":
            return Self.result(id, ["tools": Self.tools])
        case "tools/call":
            return call(
                name: params["name"] as? String ?? "",
                arguments: params["arguments"] as? [String: Any] ?? [:],
                id: id)
        default:
            return Self.error(id: id, code: -32601, message: "unknown method \(method)")
        }
    }

    // MARK: - Tools

    /// Static because the list never changes; `nonisolated(unsafe)` because the
    /// dictionaries are written once at startup and only read afterwards.
    nonisolated(unsafe) static let tools: [[String: Any]] = [
        [
            "name": "search_events",
            "description": "Search what the agents did: commands, files and rule hits in a time window.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "full-text search over command, preview and tool"
                    ],
                    "agent": [
                        "type": "string",
                        "description": "claude-code, codex, gemini, hermes, opencode, cursor or copilot"
                    ],
                    "since_days": ["type": "integer", "description": "how far back to look, default 7"],
                    "only_findings": ["type": "boolean", "description": "only events with a rule hit"],
                    "limit": ["type": "integer", "description": "max events, default 50"]
                ]
            ]
        ],
        [
            "name": "list_sessions",
            "description": "Recent sessions with their project, agent, event count and critical count.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "default 20"],
                    "agent": ["type": "string"]
                ]
            ]
        ],
        [
            "name": "get_event",
            "description": "One event by id, including the rule hits that flagged it.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ]
        ],
        [
            "name": "file_history",
            "description": "Which agents changed, read or ran commands on a file or folder, newest first "
                + "(git blame for agents). Use it before editing a file another agent may be working on.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "absolute path, or relative to cwd"],
                    "cwd": ["type": "string", "description": "folder a relative path starts from"],
                    "changes_only": ["type": "boolean", "description": "only edits and writes"],
                    "limit": ["type": "integer", "description": "default 20"]
                ],
                "required": ["path"]
            ]
        ],
        [
            "name": "audit_summary",
            "description": "How many events, findings and critical hits in a window, broken down by agent and rule.",
            "inputSchema": [
                "type": "object",
                "properties": ["since_days": ["type": "integer", "description": "default 30"]]
            ]
        ]
    ]

    private func call(name: String, arguments: [String: Any], id: Any?) -> String? {
        switch name {
        case "search_events": searchEvents(arguments, id: id)
        case "list_sessions": listSessions(arguments, id: id)
        case "get_event": getEvent(arguments, id: id)
        case "audit_summary": auditSummary(arguments, id: id)
        case "file_history": fileHistory(arguments, id: id)
        default:
            Self.error(id: id, code: -32602, message: "unknown tool \(name)")
        }
    }

    private func searchEvents(_ arguments: [String: Any], id: Any?) -> String {
        do {
            let days = arguments["since_days"] as? Int ?? 7
            var query = EventQuery(
                since: Date().addingTimeInterval(-Double(days) * 86400),
                agents: (arguments["agent"] as? String).flatMap(Agent.init(rawValue:)).map { [$0] },
                onlyFindings: arguments["only_findings"] as? Bool ?? false,
                search: arguments["query"] as? String,
                limit: Self.limit(arguments["limit"], default: 50))
            query.includeRawJSON = false
            query.excludedKinds = [.tokenUsage, .sessionStart]

            let events = try store.events(matching: query)
            let rows = events.map { event -> [String: Any] in
                var row: [String: Any] = [
                    "id": event.id,
                    "ts": ISO8601DateFormatter().string(from: event.ts),
                    "agent": event.agent.rawValue,
                    "session": event.sessionId,
                    "kind": event.kind.rawValue
                ]
                if let tool = event.tool {
                    row["tool"] = tool
                }
                if let command = event.command {
                    row["command"] = command
                }
                if let preview = event.preview {
                    row["preview"] = preview
                }
                if let cwd = event.cwd {
                    row["cwd"] = cwd
                }
                if !event.paths.isEmpty {
                    row["paths"] = event.paths
                }
                if !event.risk.isEmpty {
                    row["findings"] = event.risk.map {
                        ["rule": $0.ruleId, "severity": $0.severity.rawValue, "message": $0.englishMessage]
                    }
                }
                return row
            }
            return Self.text(id, ["count": rows.count, "events": rows])
        } catch {
            return Self.error(id: id, code: -32603, message: "search failed: \(error)")
        }
    }

    /// A client-supplied page size, between 1 and 200. Zero or a negative number
    /// would crash `prefix(_:)` or reach SQLite as `LIMIT -1`, which means "no
    /// limit" — a way around the cap.
    static func limit(_ value: Any?, default fallback: Int) -> Int {
        max(1, min(value as? Int ?? fallback, 200))
    }

    private func listSessions(_ arguments: [String: Any], id: Any?) -> String {
        do {
            let agent = (arguments["agent"] as? String).flatMap(Agent.init(rawValue:))
            let limit = Self.limit(arguments["limit"], default: 20)
            let sessions = try store.sessions(agents: agent.map { [$0] })
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
            let rows = sessions.map { session -> [String: Any] in
                var row: [String: Any] = [
                    "id": session.id,
                    "agent": session.agent.rawValue,
                    "events": session.eventCount,
                    "critical": session.criticalCount,
                    "started_at": ISO8601DateFormatter().string(from: session.startedAt)
                ]
                if let cwd = session.cwd {
                    row["cwd"] = cwd
                }
                return row
            }
            return Self.text(id, ["count": rows.count, "sessions": rows])
        } catch {
            return Self.error(id: id, code: -32603, message: "sessions failed: \(error)")
        }
    }

    private func getEvent(_ arguments: [String: Any], id: Any?) -> String {
        guard let eventID = arguments["id"] as? String else {
            return Self.error(id: id, code: -32602, message: "id is required")
        }
        do {
            guard let event = try store.event(id: eventID) else {
                return Self.error(id: id, code: -32602, message: "no event \(eventID)")
            }
            var row: [String: Any] = [
                "id": event.id,
                "ts": ISO8601DateFormatter().string(from: event.ts),
                "agent": event.agent.rawValue,
                "session": event.sessionId,
                "kind": event.kind.rawValue
            ]
            if let command = event.command {
                row["command"] = command
            }
            if let preview = event.preview {
                row["preview"] = preview
            }
            if let cwd = event.cwd {
                row["cwd"] = cwd
            }
            if !event.paths.isEmpty {
                row["paths"] = event.paths
            }
            row["findings"] = event.risk.map {
                ["rule": $0.ruleId, "severity": $0.severity.rawValue, "message": $0.englishMessage]
            }
            return Self.text(id, row)
        } catch {
            return Self.error(id: id, code: -32603, message: "lookup failed: \(error)")
        }
    }

    private func fileHistory(_ arguments: [String: Any], id: Any?) -> String {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            return Self.error(id: id, code: -32602, message: "path is required")
        }
        let cwd = arguments["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        let limit = Self.limit(arguments["limit"], default: 20)
        let changesOnly = arguments["changes_only"] as? Bool ?? false
        do {
            let target = FileHistory.Target.resolve(path, cwd: cwd)
            var touches = try FileHistory.touches(
                of: target,
                in: store,
                limit: changesOnly ? limit * 10 : limit)
            if changesOnly {
                touches = Array(touches.filter { $0.action == .changed }.prefix(limit))
            }
            let rows = touches.map { touch -> [String: Any] in
                let event = touch.event
                var row: [String: Any] = [
                    "event": event.id,
                    "ts": ISO8601DateFormatter().string(from: event.ts),
                    "agent": event.agent.rawValue,
                    "session": event.sessionId,
                    "action": touch.action.rawValue
                ]
                if let tool = event.tool {
                    row["tool"] = tool
                }
                if touch.action == .command, let command = event.command {
                    row["command"] = String(command.prefix(300))
                }
                if !event.risk.isEmpty {
                    row["findings"] = event.risk.map { ["rule": $0.ruleId, "severity": $0.severity.rawValue] }
                }
                return row
            }
            var payload: [String: Any] = ["path": target.absolute, "count": rows.count, "touches": rows]
            if let change = touches.first(where: { $0.action == .changed }) {
                payload["last_changed_by"] = change.event.agent.rawValue
                payload["last_changed_at"] = ISO8601DateFormatter().string(from: change.event.ts)
            }
            return Self.text(id, payload)
        } catch {
            return Self.error(id: id, code: -32603, message: "file history failed: \(error)")
        }
    }

    private func auditSummary(_ arguments: [String: Any], id: Any?) -> String {
        do {
            let days = arguments["since_days"] as? Int ?? 30
            let since = Date().addingTimeInterval(-Double(days) * 86400)
            var agents: [String: Int] = [:]
            for agent in Agent.allCases {
                let count = try store.eventCount(matching: EventQuery(since: since, agents: [agent]))
                if count > 0 {
                    agents[agent.rawValue] = count
                }
            }
            let findings = try store.events(matching: EventQuery(since: since, onlyFindings: true))
            var byRule: [String: Int] = [:]
            for event in findings {
                for hit in event.risk {
                    byRule[hit.ruleId, default: 0] += 1
                }
            }
            let critical = findings.filter { $0.risk.contains { $0.severity == .critical } }.count
            return try Self.text(id, [
                "window_days": days,
                "events": store.eventCount(matching: EventQuery(since: since)),
                "events_by_agent": agents,
                "findings": findings.count,
                "critical_events": critical,
                "findings_by_rule": byRule
            ])
        } catch {
            return Self.error(id: id, code: -32603, message: "summary failed: \(error)")
        }
    }

    // MARK: - Encoding

    private static func text(_ id: Any?, _ payload: [String: Any]) -> String {
        let body = (try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return result(id, ["content": [["type": "text", "text": body]]])
    }

    static func result(_ id: Any?, _ result: [String: Any]) -> String {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        return encode(response)
    }

    static func error(id: Any?, code: Int, message: String) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message]
        ]
        return encode(response)
    }

    private static func encode(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
