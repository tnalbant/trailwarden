// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// A parser turns one agent transcript file into normalized events.
///
/// Parsers are deliberately tolerant: agent transcript formats change without
/// notice, so an unreadable or unknown line is counted in
/// `ParseResult.skippedLines` instead of aborting the file.
public protocol AgentParser: Sendable {
    var agent: Agent { get }
    func parse(file: URL) throws -> ParseResult
}

/// The outcome of parsing a single transcript file.
public struct ParseResult: Sendable, Equatable {
    public let events: [Event]
    /// Lines that were not valid JSON, or whose `type` the parser does not know.
    public let skippedLines: Int

    public init(events: [Event], skippedLines: Int) {
        self.events = events
        self.skippedLines = skippedLines
    }
}
