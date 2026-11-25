// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// What an event did, in words a person uses. Seven agents name the same
/// action seven ways; the interface shows one verb.
public enum ActionVerb: String, CaseIterable, Sendable {
    case ran, edited, wrote, read, searched, said, thought, other

    public func label(_ localizer: Localizer) -> String {
        localizer.text(uiKey)
    }

    var uiKey: UIString {
        switch self {
        case .ran: .verbRan
        case .edited: .verbEdited
        case .wrote: .verbWrote
        case .read: .verbRead
        case .searched: .verbSearched
        case .said: .verbSaid
        case .thought: .verbThought
        case .other: .verbOther
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .ran: "terminal"
        case .edited: "pencil"
        case .wrote: "doc.badge.plus"
        case .read: "doc.text"
        case .searched: "magnifyingglass"
        case .said: "text.bubble"
        case .thought: "brain"
        case .other: "circle"
        }
    }
}

/// A path as shown to a person: relative to the project when it is inside it.
public struct DisplayPath: Sendable, Equatable {
    public let text: String
    public let outsideProject: Bool

    public init(text: String, outsideProject: Bool) {
        self.text = text
        self.outsideProject = outsideProject
    }
}

public enum EventPresentation {
    /// Search-like tools. `RuleEngine.canonicalTool` folds some of these into
    /// `Bash`, so they are checked before it.
    private static let searchTools: Set<String> = [
        "glob", "grep", "grep_search", "list_directory", "ls", "list_dir", "list_dir_v2",
        "glob_file_search", "file_search", "ripgrep", "rg", "codebase_search",
        "search_file_content", "web_search", "websearch", "find"
    ]
    private static let runTools: Set<String> = ["execute"]

    private static let maxSummaryLength = 200

    public static func verb(for event: Event) -> ActionVerb {
        switch event.kind {
        case .message: return .said
        case .reasoning: return .thought
        case .fileChange: return .edited
        case .toolCall, .toolResult: break
        case .sessionStart, .permission, .tokenUsage: return .other
        }
        guard let tool = event.tool else { return .other }
        if searchTools.contains(tool.lowercased()) {
            return .searched
        }
        if runTools.contains(tool.lowercased()) {
            return .ran
        }
        if tool == "apply_patch" {
            return .edited
        }
        switch RuleEngine.canonicalTool(tool) {
        case "Bash": return .ran
        case "Read": return .read
        case "Write": return .wrote
        case "Edit": return .edited
        default: return .other
        }
    }

    public static func displayPath(
        _ path: String,
        cwd: String?,
        home: String = NSHomeDirectory()) -> DisplayPath
    {
        guard path.hasPrefix("/") else {
            return DisplayPath(text: path, outsideProject: false)
        }
        let normalized = normalize(path)
        if let cwd, !cwd.isEmpty {
            let root = normalize(cwd)
            if normalized == root {
                return DisplayPath(text: ".", outsideProject: false)
            }
            let prefix = root == "/" ? "/" : root + "/"
            if normalized.hasPrefix(prefix) {
                return DisplayPath(text: String(normalized.dropFirst(prefix.count)), outsideProject: false)
            }
            return DisplayPath(text: shorten(normalized, home: home), outsideProject: true)
        }
        return DisplayPath(text: shorten(normalized, home: home), outsideProject: false)
    }

    public static func summary(for event: Event, localizer: Localizer) -> String {
        summary(verb: verb(for: event), object: object(for: event), localizer: localizer)
    }

    /// The verb and the object joined the way a row reads them. Split out so a
    /// row built from an `ActivityItem` says exactly what one built from an event does.
    public static func summary(verb: ActionVerb, object: String, localizer: Localizer) -> String {
        switch verb {
        case .said, .thought:
            object
        default:
            object.isEmpty ? verb.label(localizer) : "\(verb.label(localizer)) \(object)"
        }
    }

    /// Whether the path the summary shows lies outside the event's project, so a
    /// row can say so beside it.
    public static func touchesOutsideProject(_ event: Event) -> Bool {
        switch verb(for: event) {
        case .read, .edited, .wrote, .searched:
            event.paths.first.map { displayPath($0, cwd: event.cwd).outsideProject } ?? false
        default:
            false
        }
    }

    /// The thing the event touched, on one line and without the verb. Empty when
    /// the event carries nothing to show.
    public static func object(for event: Event) -> String {
        let verb = verb(for: event)
        let object: String? = switch verb {
        case .said, .thought:
            event.preview ?? event.command
        case .ran:
            event.command ?? event.paths.first ?? event.preview
        case .read, .edited, .wrote, .searched:
            if let path = event.paths.first {
                displayPath(path, cwd: event.cwd).text
            } else if verb == .searched {
                event.command ?? event.preview
            } else {
                event.command
            }
        case .other:
            event.command ?? event.paths.first ?? event.preview
        }
        return oneLine(object ?? "")
    }

    public static func ruleTitle(_ hit: RiskHit, localizer: Localizer) -> String {
        RuleLocalization.text(forRule: hit.ruleId, language: localizer.language)?.title ?? hit.ruleId
    }

    // MARK: - Helpers

    private static func normalize(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        for alias in ["/private/tmp", "/private/var"] {
            if value == alias || value.hasPrefix(alias + "/") {
                value = String(value.dropFirst("/private".count))
                break
            }
        }
        return value
    }

    private static func shorten(_ path: String, home: String) -> String {
        let homePath = normalize(home)
        if homePath.count > 1 {
            if path == homePath {
                return "~"
            }
            if path.hasPrefix(homePath + "/") {
                return "~" + path.dropFirst(homePath.count)
            }
        }
        return Redactor().shortenHome(path)
    }

    private static func oneLine(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > maxSummaryLength else { return collapsed }
        return String(collapsed.prefix(maxSummaryLength - 1)) + "…"
    }
}
