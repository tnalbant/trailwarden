// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class FileHistoryTests: XCTestCase {
    private let repo = "/Users/demo/dev/aurora"

    private func event(
        _ id: String,
        minutesAgo: Double,
        agent: Agent,
        tool: String,
        command: String? = nil,
        paths: [String] = [],
        session: String = "s") -> Event
    {
        Event(
            id: id,
            ts: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60),
            agent: agent,
            sessionId: session,
            kind: .toolCall,
            cwd: repo,
            tool: tool,
            command: command,
            paths: paths,
            preview: command)
    }

    private func store(_ events: [Event]) throws -> EventStore {
        let store = try EventStore(inMemory: true)
        try store.insert(events: events)
        return store
    }

    private func file(_ relative: String, directory: Bool = false) -> FileHistory.Target {
        FileHistory.Target(absolute: repo + "/" + relative, isDirectory: directory)
    }

    func testEditsReadsAndCommandsAreToldApart() throws {
        let store = try store([
            event(
                "edit",
                minutesAgo: 1,
                agent: .claudeCode,
                tool: "Edit",
                paths: [repo + "/Sources/App.swift"]),
            event(
                "patch",
                minutesAgo: 5,
                agent: .codex,
                tool: "apply_patch",
                command: "*** Begin Patch\n*** Update File: \(repo)/Sources/App.swift",
                paths: [repo + "/Sources/App.swift"],
                session: "c"),
            event(
                "read",
                minutesAgo: 9,
                agent: .hermes,
                tool: "read_file",
                paths: [repo + "/Sources/App.swift"]),
            event(
                "sed",
                minutesAgo: 12,
                agent: .gemini,
                tool: "run_shell_command",
                command: "sed -i '' 's/a/b/' Sources/App.swift")
        ])

        let touches = try FileHistory.touches(of: file("Sources/App.swift"), in: store)

        XCTAssertEqual(touches.map(\.event.id), ["edit", "patch", "read", "sed"])
        XCTAssertEqual(touches.map(\.action), [.changed, .changed, .read, .command])
    }

    func testASimilarNameIsNotTheSameFile() throws {
        let store = try store([
            event(
                "other",
                minutesAgo: 1,
                agent: .claudeCode,
                tool: "Edit",
                paths: [repo + "/Sources/MyApp.swift"]),
            event(
                "cmd",
                minutesAgo: 2,
                agent: .codex,
                tool: "exec_command",
                command: "swiftlint Sources/MyApp.swift"),
            event(
                "data",
                minutesAgo: 3,
                agent: .codex,
                tool: "exec_command",
                command: "cat Sources/App.swift.orig"),
            event("elsewhere", minutesAgo: 4, agent: .codex, tool: "Edit", paths: ["/tmp/Sources/App.swift"])
        ])

        XCTAssertTrue(try FileHistory.touches(of: file("Sources/App.swift"), in: store).isEmpty)
    }

    func testAFolderCollectsEverythingUnderIt() throws {
        let store = try store([
            event("a", minutesAgo: 1, agent: .claudeCode, tool: "Write", paths: [repo + "/Sources/A.swift"]),
            event("b", minutesAgo: 2, agent: .codex, tool: "Edit", paths: [repo + "/Sources/Deep/B.swift"]),
            event("c", minutesAgo: 3, agent: .codex, tool: "Edit", paths: [repo + "/SourcesOld/C.swift"])
        ])

        let touches = try FileHistory.touches(of: file("Sources", directory: true), in: store)

        XCTAssertEqual(touches.map(\.event.id), ["a", "b"])
    }

    func testHomeShortenedAndRelativeSpellingsMatch() throws {
        let store = try store([
            event(
                "tilde",
                minutesAgo: 1,
                agent: .hermes,
                tool: "write_file",
                paths: ["~/dev/aurora/notes.md"]),
            event("relative", minutesAgo: 2, agent: .claudeCode, tool: "Edit", paths: ["notes.md"])
        ])

        let touches = try FileHistory.touches(of: file("notes.md"), in: store)

        XCTAssertEqual(touches.map(\.event.id), ["tilde", "relative"])
    }

    func testPatchTextNamingAFileIsNotATouch() throws {
        let store = try store([
            event(
                "patch",
                minutesAgo: 1,
                agent: .codex,
                tool: "apply_patch",
                command: "*** Begin Patch\n*** Update File: x.py\n+# see Sources/App.swift",
                paths: [repo + "/x.py"])
        ])

        XCTAssertTrue(try FileHistory.touches(of: file("Sources/App.swift"), in: store).isEmpty)
    }

    func testResolveExpandsHomeAndRelativePaths() {
        let home = NSHomeDirectory()
        XCTAssertEqual(FileHistory.Target.resolve("~/x.txt", cwd: "/tmp").absolute, home + "/x.txt")
        XCTAssertEqual(FileHistory.Target.resolve("a/../b.txt", cwd: "/work").absolute, "/work/b.txt")
        XCTAssertEqual(FileHistory.Target.resolve("/abs/c.txt/", cwd: "/work").absolute, "/abs/c.txt")
    }

    func testTheMCPToolAnswersTheSameQuestion() throws {
        let store = try store([
            event("edit", minutesAgo: 1, agent: .claudeCode, tool: "Edit", paths: [repo + "/README.md"])
        ])
        let router = MCPRouter(store: store)
        let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"file_history","arguments":{"path":"README.md","cwd":"/Users/demo/dev/aurora"}}}"#

        let response = try XCTUnwrap(router.handle(request))

        XCTAssertTrue(response.contains(#"\"last_changed_by\":\"claude-code\""#), response)
        XCTAssertTrue(response.contains(#"\"action\":\"changed\""#), response)
    }
}
