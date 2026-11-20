// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// What a token event adds up to.
///
/// The agents disagree on the shape of this line: Claude writes "in 1,234 / out
/// 567", Codex writes "input 1234 output 567" or only "total tokens: 95336339",
/// Gemini records a JSON blob. Rather than guess a currency, Trailwarden counts
/// tokens — a number that is in the transcript — and never invents a price.
public struct TokenTotals: Sendable, Equatable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheRead: Int = 0
    public var cacheWrite: Int = 0
    public var total: Int = 0
    public var events: Int = 0

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        total: Int = 0,
        events: Int = 0)
    {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.total = total
        self.events = events
    }

    /// The counts of one stored token event.
    public init(_ count: TokenCount) {
        self.init(
            input: count.input,
            output: count.output,
            cacheRead: count.cacheRead,
            cacheWrite: count.cacheWrite,
            events: 1)
    }

    /// `nil` when the text carries no number at all — an unparsable line must
    /// not quietly count as zero tokens.
    public init?(preview: String) {
        guard let numbers = Self.numbers(in: preview) else { return nil }
        self = numbers
    }

    /// Tokens the model actually read and wrote. A bare "total tokens" line is
    /// the agent's running context size, which repeats on every turn — adding
    /// those up would invent billions of tokens that were never processed.
    public var processed: Int {
        let (sum, overflow) = (input + output).addingReportingOverflow(cacheRead + cacheWrite)
        return overflow ? Int.max : sum
    }

    /// The largest context a session reported, kept as its own number.
    public var peakContext: Int {
        total
    }

    static func numbers(in text: String) -> TokenTotals? {
        let lowered = text.lowercased()
        var totals = TokenTotals(events: 1)

        // "20705 in / 90 out" puts the number first; "in 1,234 / out 567" puts
        // the label first. Both shapes are in the wild, so both are tried.
        if let input = number(before: "in", in: lowered) {
            totals.input = max(totals.input, input)
        }
        if let output = number(before: "out", in: lowered) {
            totals.output = max(totals.output, output)
        }

        let labelled: [(needle: String, set: (Int) -> Void)] = [
            ("input", { totals.input = max(totals.input, $0) }),
            ("in ", { totals.input = max(totals.input, $0) }),
            ("output", { totals.output = max(totals.output, $0) }),
            ("out ", { totals.output = max(totals.output, $0) }),
            // "total tokens: 50" — the label and the number are a few words apart.
            ("total tokens", { totals.total = max(totals.total, $0) }),
            ("total", { totals.total = max(totals.total, $0) })
        ]

        var found = totals.input > 0 || totals.output > 0
        for (needle, apply) in labelled {
            guard let number = number(after: needle, in: lowered) else { continue }
            apply(number)
            found = true
        }

        if !found {
            // A bare number is still a token count; anything else is noise.
            guard let number = number(after: "", in: lowered) else { return nil }
            totals.total = number
            found = true
        }

        return found ? totals : nil
    }

    private static func number(before needle: String, in text: String) -> Int? {
        let pattern = "(\\d[\\d,]*)\\s+" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[captured].replacingOccurrences(of: ",", with: ""))
    }

    private static func number(after needle: String, in text: String) -> Int? {
        let gap = needle.hasPrefix("total") ? "\\D{0,16}" : "\\D{0,3}"
        let pattern = needle.isEmpty
            ? "(\\d[\\d,]{2,})"
            : NSRegularExpression.escapedPattern(for: needle) + gap + "(\\d[\\d,]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        let digits = text[captured].replacingOccurrences(of: ",", with: "")
        return Int(digits)
    }
}

/// One day of usage for the chart.
public struct DailyTokens: Sendable, Equatable, Identifiable {
    public let day: Date
    public let tokens: Int
    public var id: Date {
        day
    }
}

public extension EventStore {
    /// Only the counters, and only the columns the counters need.
    private func tokenEvents(since: Date) throws -> [Event] {
        var query = EventQuery(
            since: since,
            excludedKinds: Set(EventKind.allCases).subtracting([.tokenUsage]))
        query.includeRawJSON = false
        return try events(matching: query)
    }

    /// One stored token event as counters: the token columns when the parser
    /// filled them, the preview line otherwise.
    private static func totals(of event: Event) -> TokenTotals? {
        if let usage = event.usage {
            return TokenTotals(usage)
        }
        return event.preview.flatMap(TokenTotals.init(preview:))
    }

    /// Tokens per agent, read from the stored token events.
    func tokenTotalsByAgent(since: Date) throws -> [Agent: TokenTotals] {
        let events = try tokenEvents(since: since)
        var result: [Agent: TokenTotals] = [:]
        for event in events {
            guard let totals = Self.totals(of: event) else { continue }
            var existing = result[event.agent] ?? TokenTotals()
            existing.input += totals.input
            existing.output += totals.output
            existing.cacheRead += totals.cacheRead
            existing.cacheWrite += totals.cacheWrite
            existing.total = max(existing.total, totals.total)
            existing.events += 1
            result[event.agent] = existing
        }
        return result
    }

    /// Tokens per agent and model, for the events that name their model. The
    /// key is what the agent wrote ("claude-opus-4-1", "gpt-5-codex"); events
    /// without a model are left out rather than guessed.
    func tokenCountsByModel(since: Date) throws -> [ModelUsage] {
        var result: [ModelUsage.Key: TokenCount] = [:]
        for event in try tokenEvents(since: since) {
            guard let usage = event.usage, let model = usage.model else { continue }
            let key = ModelUsage.Key(agent: event.agent, model: model)
            var existing = result[key] ?? TokenCount(model: model)
            existing.add(usage)
            result[key] = existing
        }
        return result
            .map { ModelUsage(agent: $0.key.agent, model: $0.key.model, tokens: $0.value) }
            .sorted { $0.tokens.processed > $1.tokens.processed }
    }

    /// Tokens per calendar day, oldest first, for the last `days` days.
    func dailyTokens(since: Date, calendar: Calendar = .current) throws -> [DailyTokens] {
        let events = try tokenEvents(since: since)
        var byDay: [Date: Int] = [:]
        for event in events {
            guard let totals = Self.totals(of: event) else { continue }
            let day = calendar.startOfDay(for: event.ts)
            byDay[day, default: 0] += totals.processed
        }
        return byDay
            .map { DailyTokens(day: $0.key, tokens: $0.value) }
            .sorted { $0.day < $1.day }
    }
}

/// What one agent spent on one model.
public struct ModelUsage: Sendable, Equatable, Identifiable {
    struct Key: Hashable {
        let agent: Agent
        let model: String
    }

    public let agent: Agent
    public let model: String
    public let tokens: TokenCount
    public var id: String {
        agent.rawValue + "|" + model
    }
}
