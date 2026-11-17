// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// Codex "code mode" wraps every tool call in a JavaScript program. These are the
/// shapes seen in real rollouts, rewritten with invented paths.
final class CodexCodeModeTests: XCTestCase {
    func testOneLineExecCommandWithQuotedKeys() {
        let source = #"""
        text(await tools.exec_command({cmd:"tail -18 build.log; rg -n 'error:' build.log | tail -5","workdir":"/repo","max_output_tokens":1300}));
        """#
        let call = CodexCodeMode.read(source)
        XCTAssertEqual(call?.commands, ["tail -18 build.log; rg -n 'error:' build.log | tail -5"])
        XCTAssertEqual(call?.workdir, "/repo")
        XCTAssertEqual(call?.displayTool, "exec_command")
    }

    func testMultiLineObjectWithEscapedNewline() {
        let source = """
        const r = await tools.exec_command({
          cmd: "xcrun simctl boot ABC\\nxcrun simctl bootstatus ABC -b",
          workdir: "/repo",
          yield_time_ms: 30000
        });
        text(r.output);
        """
        let call = CodexCodeMode.read(source)
        XCTAssertEqual(call?.commands, ["xcrun simctl boot ABC\nxcrun simctl bootstatus ABC -b"])
    }

    func testEscapedQuotesInsideTheCommand() {
        let source = #"""
        const r = await tools.exec_command({cmd:"rg \"Test Case .* (failed|passed)\" /tmp/run.log | tail -20",workdir:"/repo"});
        """#
        XCTAssertEqual(
            CodexCodeMode.read(source)?.commands,
            [#"rg "Test Case .* (failed|passed)" /tmp/run.log | tail -20"#])
    }

    func testTwoCommandsInOneProgram() {
        let source = """
        await tools.exec_command({cmd:"git status --short"});
        await tools.exec_command({cmd:'git diff --stat'});
        """
        XCTAssertEqual(CodexCodeMode.read(source)?.commands, ["git status --short", "git diff --stat"])
    }

    func testPatchHeadersBecomePaths() {
        let source = #"""
        const patch = "*** Begin Patch\n*** Update File: /repo/xclient.py\n@@\n-a\n+b\n*** Add File: /repo/tests/test_x.py\n+ok\n*** End Patch";
        text(await tools.apply_patch(patch));
        """#
        let call = CodexCodeMode.read(source)
        XCTAssertEqual(call?.patchedPaths, ["/repo/tests/test_x.py", "/repo/xclient.py"].sorted { lhs, _ in
            lhs.contains("tests")
        })
        XCTAssertEqual(call?.displayTool, "apply_patch")
        XCTAssertTrue(call?.commands.isEmpty ?? false)
    }

    func testOtherToolsKeepTheirName() {
        let source = """
        const r = await tools.mcp__codegraph__explore({projectPath:"/repo",query:"TodayView"});
        """
        XCTAssertEqual(CodexCodeMode.read(source)?.displayTool, "mcp__codegraph__explore")
    }

    func testPollingStdinIsNotAToolOfItsOwn() {
        let source = "const r = await tools.write_stdin({session_id:7548,chars:\"\"}); text(r.output);"
        let call = CodexCodeMode.read(source)
        XCTAssertEqual(call?.tools, ["write_stdin"])
        XCTAssertNil(call?.displayTool)
    }

    func testPlainShellIsNotCodeMode() {
        XCTAssertNil(CodexCodeMode.read("git status --short"))
    }

    func testParserStoresTheShellCommandSoRulesSeeIt() throws {
        let program = #"text(await tools.exec_command({cmd:"cd /tmp && rm -rf ~","workdir":"/repo"}));"#
        let line: [String: Any] = [
            "timestamp": "2026-11-14T09:00:01.000Z",
            "type": "response_item",
            "payload": ["type": "custom_tool_call", "name": "exec", "call_id": "c1", "input": program]
        ]
        let meta: [String: Any] = [
            "timestamp": "2026-11-14T09:00:00.000Z",
            "type": "session_meta",
            "payload": ["id": "s-1", "cwd": "/repo"]
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-code-mode-\(UUID().uuidString).jsonl")
        let text = try [meta, line]
            .map { try String(decoding: JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            .joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let events = try CodexParser().parse(file: url).events.filter { $0.kind == .toolCall }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.command, "cd /tmp && rm -rf ~")
        XCTAssertEqual(events.first?.tool, "exec_command")

        let hits = try RuleEngine.builtIn().hits(for: XCTUnwrap(events.first))
        XCTAssertEqual(hits.map(\.ruleId), ["R1"])
    }
}
