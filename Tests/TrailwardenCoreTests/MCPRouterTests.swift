// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class MCPRouterTests: XCTestCase {
    private func makeRouter() throws -> MCPRouter {
        let store = try EventStore(inMemory: true)
        let now = Date()
        try store.insert(events: [
            Event(id: "e1", ts: now, agent: .codex, sessionId: "s1", kind: .toolCall,
                  cwd: "/Users/demo/dev/aurora", tool: "Bash", command: "rm -rf /",
                  paths: [], preview: "rm -rf /",
                  risk: [RiskHit(ruleId: "R1", severity: .critical, message: "recursive delete")],
                  rawJSON: nil),
            Event(id: "e2", ts: now, agent: .hermes, sessionId: "s2", kind: .message,
                  cwd: "/Users/demo/dev/ledger", preview: "ship it", risk: [], rawJSON: nil),
            Event(id: "e3", ts: now, agent: .hermes, sessionId: "s2", kind: .tokenUsage,
                  preview: "tokens: 100 in / 10 out", risk: [], rawJSON: nil),
        ])
        return MCPRouter(store: store)
    }

    private func object(_ line: String?) throws -> [String: Any] {
        let text = try XCTUnwrap(line)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testInitializeAdvertisesTools() throws {
        let router = try makeRouter()
        let response = try object(router.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#))
        let result = try XCTUnwrap(response["result"] as? [String: Any])

        XCTAssertEqual(result["protocolVersion"] as? String, MCPRouter.protocolVersion)
        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, "trailwarden")
    }

    func testToolsListHasFourTools() throws {
        let router = try makeRouter()
        let response = try object(router.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])

        XCTAssertEqual(tools.count, 4)
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }),
                       ["search_events", "list_sessions", "get_event", "audit_summary"])
        for tool in tools {
            XCTAssertNotNil(tool["inputSchema"], "\(tool["name"] ?? "?") needs a schema")
        }
    }

    func testSearchFindsTheFinding() throws {
        let router = try makeRouter()
        let line = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_events","arguments":{"only_findings":true}}}"#
        let response = try object(router.handle(line))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let body = try XCTUnwrap(content.first?["text"] as? String)

        XCTAssertTrue(body.contains("R1"))
        XCTAssertTrue(body.contains("rm -rf /"))
    }

    func testSearchSkipsTokenCounters() throws {
        let router = try makeRouter()
        let line = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_events","arguments":{}}}"#
        let response = try object(router.handle(line))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let body = try XCTUnwrap(content.first?["text"] as? String)

        XCTAssertFalse(body.contains("token_usage"))
    }

    func testGetEventById() throws {
        let router = try makeRouter()
        let line = #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_event","arguments":{"id":"e2"}}}"#
        let response = try object(router.handle(line))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let body = try XCTUnwrap(content.first?["text"] as? String)

        XCTAssertTrue(body.contains("ship it"))
        XCTAssertTrue(body.contains("hermes"))
    }

    func testAuditSummaryCounts() throws {
        let router = try makeRouter()
        let line = #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"audit_summary","arguments":{"since_days":1}}}"#
        let response = try object(router.handle(line))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let body = try XCTUnwrap(content.first?["text"] as? String)

        XCTAssertTrue(body.contains("\"critical_events\":1"))
        XCTAssertTrue(body.contains("R1"))
    }

    func testNotificationsGetNoResponse() throws {
        let router = try makeRouter()
        XCTAssertNil(router.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testUnknownMethodIsAnError() throws {
        let router = try makeRouter()
        let response = try object(router.handle(#"{"jsonrpc":"2.0","id":7,"method":"tools/nope"}"#))
        let error = try XCTUnwrap(response["error"] as? [String: Any])

        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testGarbageIsAParseError() throws {
        let router = try makeRouter()
        let response = try object(router.handle("not json"))
        let error = try XCTUnwrap(response["error"] as? [String: Any])

        XCTAssertEqual(error["code"] as? Int, -32700)
    }
}
