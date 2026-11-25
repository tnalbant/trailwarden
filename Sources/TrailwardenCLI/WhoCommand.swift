// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import ArgumentParser
import Foundation
import TrailwardenCore

/// `trailwarden who <path>` — which agent touched this file, when, and how.
struct WhoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "who",
        abstract: "Show which agents changed, read or ran commands on a file or folder.",
        discussion: """
        Reads the index only; run `trailwarden scan` first to bring it up to date.
        A folder lists everything under it. Exit status is 0 whether or not the
        path was touched.
        """)

    @OptionGroup var store: StoreOptions

    @Argument(help: "A file or folder, absolute or relative to the current directory.")
    var path: String

    @Option(name: .long, help: "How many touches to list.")
    var limit = 20

    @Flag(name: .long, help: "Only edits and writes, not reads or commands.")
    var changesOnly = false

    @Flag(name: .long, help: "Print JSON.")
    var json = false

    func run() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1") }
        // Multiplied below; a huge value would overflow instead of meaning "all".
        let limit = min(limit, 10000)
        let target = FileHistory.Target.resolve(path, cwd: FileManager.default.currentDirectoryPath)
        let database = try store.open()
        var touches = try FileHistory.touches(
            of: target,
            in: database,
            limit: changesOnly ? limit * 10 : limit)
        if changesOnly {
            touches = Array(touches.filter { $0.action == .changed }.prefix(limit))
        }

        if json {
            try Output.write(jsonReport(target: target, touches: touches))
        } else {
            Output.write(textReport(target: target, touches: touches))
        }
    }

    private func textReport(target: FileHistory.Target, touches: [FileTouch]) -> String {
        let shown = Self.home(target.absolute)
        guard !touches.isEmpty else {
            return "\(shown)\n  no agent touched this \(target.isDirectory ? "folder" : "file") in the index."
        }
        var lines = [shown]
        if let change = touches.first(where: { $0.action == .changed }) {
            let event = change.event
            var location = ActivityDigest.project(from: event.cwd) ?? "-"
            if let branch = event.gitBranch, !branch.isEmpty {
                location += " (\(branch))"
            }
            lines.append(
                "  last changed by \(event.agent.rawValue) · \(Self.stamp(event.ts)) · "
                    + "\(event.tool ?? "-") · \(location)")
            if let resume = ResumeCommand.command(
                agent: event.agent,
                sessionId: event.sessionId,
                cwd: event.cwd)
            {
                lines.append("  resume: \(resume)")
            }
        } else {
            lines.append("  never changed by an agent in the index — only read or named in commands.")
        }

        let agents = Set(touches.map(\.event.agent)).count
        let sessions = Set(touches.map(\.event.sessionId)).count
        lines.append("")
        lines.append(
            "  \(touches.count) touch\(touches.count == 1 ? "" : "es") by \(agents) "
                +
                "agent\(agents == 1 ? "" : "s") in \(sessions) session\(sessions == 1 ? "" : "s"), newest first:")
        for touch in touches {
            let event = touch.event
            let flag = event.activeRisk.map(\.severity).max().map { " [\($0.rawValue)]" } ?? ""
            var detail = event.tool ?? "-"
            if touch.action == .command, let command = event.command {
                detail = command.replacingOccurrences(of: "\n", with: " ⏎ ")
            } else if target.isDirectory, let path = event.paths.first {
                detail += "  " + Self.home(path)
            }
            lines.append(
                "  \(Self.stamp(event.ts))  \(event.agent.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0))"
                    + " \(touch.action.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))"
                    + " \(String(detail.prefix(90)))\(flag)")
        }
        return lines.joined(separator: "\n")
    }

    private func jsonReport(target: FileHistory.Target, touches: [FileTouch]) throws -> String {
        let rows: [[String: Any]] = touches.map { touch in
            let event = touch.event
            var row: [String: Any] = [
                "event": event.id,
                "ts": Output.timestamp(event.ts),
                "agent": event.agent.rawValue,
                "session": event.sessionId,
                "action": touch.action.rawValue
            ]
            if let tool = event.tool {
                row["tool"] = tool
            }
            if let command = event.command, touch.action == .command {
                row["command"] = command
            }
            if let cwd = event.cwd {
                row["cwd"] = cwd
            }
            if !event.activeRisk.isEmpty {
                row["findings"] = event.activeRisk
                    .map { ["rule": $0.ruleId, "severity": $0.severity.rawValue] }
            }
            if let resume = ResumeCommand.command(
                agent: event.agent,
                sessionId: event.sessionId,
                cwd: event.cwd)
            {
                row["resume"] = resume
            }
            return row
        }
        let payload: [String: Any] = [
            "schema": TrailwardenVersion.schema,
            "path": target.absolute,
            "directory": target.isDirectory,
            "touches": rows
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func home(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
