// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// A parser turns one agent transcript file into normalized events.
///
/// Parsers are deliberately tolerant: agent transcript formats change without
/// notice, so an unreadable or unknown line is counted in
/// `ParseResult.skippedLines` instead of aborting the file.
public protocol AgentParser: Sendable {
    var agent: Agent { get }
    /// Transcript files this parser understands; the scanner skips the rest.
    var fileExtension: String { get }
    func parse(file: URL) throws -> ParseResult
    /// Whether the scanner and the live watcher should hand this file over.
    func accepts(_ url: URL) -> Bool
}

public extension AgentParser {
    var fileExtension: String {
        "jsonl"
    }

    func accepts(_ url: URL) -> Bool {
        url.pathExtension == fileExtension
    }
}

/// The outcome of parsing a single transcript file.
public struct ParseResult: Sendable, Equatable {
    public let events: [Event]
    /// Lines that were not valid JSON, or whose `type` the parser does not know.
    public let skippedLines: Int
    /// Session id to the best title found in this file; an agent-written
    /// title beats the first user message.
    public let titles: [String: SessionTitle]

    public init(events: [Event], skippedLines: Int, titles: [String: SessionTitle] = [:]) {
        self.events = events
        self.skippedLines = skippedLines
        self.titles = titles
    }
}
