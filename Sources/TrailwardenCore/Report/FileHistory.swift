// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// One time an agent did something to a file.
public struct FileTouch: Sendable, Equatable, Identifiable {
    public enum Action: String, Sendable, Codable {
        /// An edit or write tool changed it.
        case changed
        /// A read tool opened it.
        case read
        /// A shell command named it.
        case command
    }

    public let event: Event
    public let action: Action

    public var id: String {
        event.id
    }
}

/// "Who touched this file?" — `git blame` for agents. Several agents working in
/// the same repository leave a file changed without saying which one did it;
/// the index already knows, because every edit carries its path and every
/// command its text.
public enum FileHistory {
    /// The file (or folder) as the agents might have written it: absolute, and
    /// with the home folder shortened to `~`.
    public struct Target: Sendable, Equatable {
        public let absolute: String
        public let isDirectory: Bool

        public init(absolute: String, isDirectory: Bool) {
            var path = absolute
            while path.count > 1, path.hasSuffix("/") {
                path.removeLast()
            }
            self.absolute = path
            self.isDirectory = isDirectory
        }

        /// Resolves a path the way a shell would: relative to `cwd`, `~` expanded.
        public static func resolve(_ raw: String, cwd: String) -> Target {
            var path = raw
            if path == "~" || path.hasPrefix("~/") {
                path = NSHomeDirectory() + path.dropFirst()
            } else if !path.hasPrefix("/") {
                path = (cwd as NSString).appendingPathComponent(path)
            }
            let standardized = (path as NSString).standardizingPath
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory)
            return Target(absolute: standardized, isDirectory: exists && isDirectory.boolValue)
        }

        /// Spellings to look for. `/private/tmp` and `/tmp` are the same folder
        /// on macOS, and stored paths may already be shortened to `~`.
        var spellings: [String] {
            var result = [absolute]
            if absolute.hasPrefix("/private/") {
                result.append(String(absolute.dropFirst("/private".count)))
            } else if absolute.hasPrefix("/tmp/") || absolute.hasPrefix("/var/") {
                result.append("/private" + absolute)
            }
            for root in ["/Users/", "/home/"] where absolute.hasPrefix(root) {
                let rest = absolute.dropFirst(root.count)
                if let slash = rest.firstIndex(of: "/") {
                    result.append("~" + rest[slash...])
                } else {
                    result.append("~")
                }
            }
            return result
        }

        var name: String {
            (absolute as NSString).lastPathComponent
        }
    }

    /// Newest first. Only tool calls count: a message that mentions a file is
    /// talk, not a touch.
    public static func touches(
        of target: Target,
        in store: EventStore,
        limit: Int = 50) throws -> [FileTouch]
    {
        let candidates = try store.fileHistoryCandidates(
            name: target.name,
            scanLimit: max(min(limit, 10000) * 40, 2000))
        var result: [FileTouch] = []
        for event in candidates {
            guard let action = action(for: event, target: target) else { continue }
            result.append(FileTouch(event: event, action: action))
            if result.count >= limit {
                break
            }
        }
        return result
    }

    /// Whether `event` touches the target, and how. `nil` when it only shares
    /// the file name with it.
    static func action(for event: Event, target: Target) -> FileTouch.Action? {
        let spellings = target.spellings
        let tool = RuleEngine.canonicalTool(event.tool)

        func matches(_ path: String) -> Bool {
            let absolute = path.hasPrefix("/") || path.hasPrefix("~")
                ? path
                : event.cwd.map { ($0 as NSString).appendingPathComponent(path) } ?? path
            let standardized = absolute.hasPrefix("~") ? absolute : (absolute as NSString).standardizingPath
            return spellings.contains { spelling in
                standardized == spelling || (target.isDirectory && standardized.hasPrefix(spelling + "/"))
            }
        }

        if event.paths.contains(where: matches) {
            switch tool {
            case "Write", "Edit": return .changed
            case "Read": return .read
            default: return .command
            }
        }

        guard let command = event.command else { return nil }
        // Edit tools carry patch text as the command; a file named in it was
        // not necessarily touched.
        if tool == "Write" || tool == "Edit" {
            return nil
        }
        var needles = spellings
        if let cwd = event.cwd, target.absolute.hasPrefix(cwd + "/") {
            needles.append(String(target.absolute.dropFirst(cwd.count + 1)))
        }
        let mentioned = needles.contains { needle in
            guard let range = command.range(of: needle) else { return false }
            // `a.swift` must not match `data.swift`, nor `src/a` match `src/ab`.
            let before = range.lowerBound == command.startIndex
                ? nil
                : command[command.index(before: range.lowerBound)]
            let after = range.upperBound == command.endIndex ? nil : command[range.upperBound]
            let boundary: (Character?) -> Bool = { character in
                guard let character else { return true }
                return !(character.isLetter || character.isNumber || character == "_" || character == "-"
                    || character == ".")
            }
            let beforeOK = before == nil || before == "/" || boundary(before)
            let afterOK = boundary(after) || (target.isDirectory && after == "/")
            return beforeOK && afterOK
        }
        return mentioned ? .command : nil
    }
}

public extension EventStore {
    /// Tool calls whose paths or command contain `name`, newest first. A coarse
    /// filter; `FileHistory` decides which ones really touch the file.
    func fileHistoryCandidates(name: String, scanLimit: Int) throws -> [Event] {
        let pattern = "%" + name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        let statement = try prepareRowStatement("""
        SELECT events.id, events.ts, events.agent, events.session_id, events.kind, events.cwd,
               events.git_branch, events.tool, events.command, events.paths, events.preview,
               events.risk, NULL AS raw_json
        FROM events
        WHERE events.kind = 'tool_call'
          AND (events.command LIKE ? ESCAPE '\\'
               OR EXISTS (SELECT 1 FROM json_each(events.paths) WHERE json_each.value LIKE ? ESCAPE '\\'))
        ORDER BY events.ts DESC, events.id ASC
        LIMIT ?
        """)
        try statement.bind([.text(pattern), .text(pattern), .int(scanLimit)])
        var result: [Event] = []
        while try statement.step() {
            if let event = Self.event(from: statement) {
                result.append(event)
            }
        }
        return result
    }
}
