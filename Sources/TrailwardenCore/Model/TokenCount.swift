// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

/// The tokens one model call (or one session, for agents that only keep a
/// session total) read and wrote, split the way providers bill them.
///
/// The agents disagree on what "input" means: Anthropic counts cache reads and
/// cache writes apart from `input_tokens`, OpenAI folds cached tokens into
/// `input_tokens`. Parsers normalize to the Anthropic shape, so the four buckets
/// never overlap and adding them up never counts a token twice:
///
/// - `input` — fresh prompt tokens, not served from a cache
/// - `cacheRead` — prompt tokens served from the provider's cache
/// - `cacheWrite` — prompt tokens written into the cache
/// - `output` — generated tokens, reasoning included
///
/// `reasoning` is the part of `output` the model spent thinking; it is shown,
/// never added on top.
public struct TokenCount: Codable, Sendable, Hashable {
    public var model: String?
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var reasoning: Int

    public init(
        model: String? = nil,
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        reasoning: Int = 0)
    {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmed?.isEmpty == false ? trimmed : nil
        // A negative count is a broken line, not a refund.
        self.input = max(0, input)
        self.output = max(0, output)
        self.cacheRead = max(0, cacheRead)
        self.cacheWrite = max(0, cacheWrite)
        self.reasoning = max(0, min(reasoning, self.output))
    }

    /// Every token the model handled for this call.
    public var processed: Int {
        Self.sum(input, cacheRead, cacheWrite, output)
    }

    /// Prompt tokens of any kind.
    public var prompt: Int {
        Self.sum(input, cacheRead, cacheWrite)
    }

    public var isEmpty: Bool {
        processed == 0
    }

    /// The short line the timeline shows; it also keeps the older preview-based
    /// counters working ("N in / M out").
    public var preview: String {
        var text = "tokens: \(prompt) in / \(output) out"
        var details: [String] = []
        if cacheRead > 0 {
            details.append("cache read \(cacheRead)")
        }
        if cacheWrite > 0 {
            details.append("cache write \(cacheWrite)")
        }
        if reasoning > 0 {
            details.append("reasoning \(reasoning)")
        }
        if !details.isEmpty {
            text += " (" + details.joined(separator: ", ") + ")"
        }
        if let model {
            text += " · \(model)"
        }
        return text
    }

    /// Adds another count into this one; the model is kept only when both agree.
    public mutating func add(_ other: TokenCount) {
        input = Self.sum(input, other.input)
        output = Self.sum(output, other.output)
        cacheRead = Self.sum(cacheRead, other.cacheRead)
        cacheWrite = Self.sum(cacheWrite, other.cacheWrite)
        reasoning = Self.sum(reasoning, other.reasoning)
        if model != other.model {
            model = model ?? other.model
        }
    }

    /// The difference between two running totals, for agents that only log the
    /// session total so far. A total that went down (a reset) yields the new
    /// total as it is.
    public func since(_ earlier: TokenCount) -> TokenCount {
        func delta(_ now: Int, _ before: Int) -> Int {
            now >= before ? now - before : now
        }
        return TokenCount(
            model: model ?? earlier.model,
            input: delta(input, earlier.input),
            output: delta(output, earlier.output),
            cacheRead: delta(cacheRead, earlier.cacheRead),
            cacheWrite: delta(cacheWrite, earlier.cacheWrite),
            reasoning: delta(reasoning, earlier.reasoning))
    }

    /// A count from a JSON value: integers, floats and numeric strings, never
    /// negative, never a trap on a value too large for `Int`.
    public static func number(_ value: Any?) -> Int {
        switch value {
        case let number as Int: max(0, number)
        case let number as Double: max(0, Int(saturating: number))
        case let text as String: max(0, Int(text) ?? 0)
        default: 0
        }
    }

    /// An OpenAI-style usage block (Codex, Gemini): `input_tokens` includes the
    /// cached tokens and `output_tokens` includes the reasoning ones.
    public static func includingCache(
        model: String?,
        input: Int,
        cached: Int,
        cacheWrite: Int = 0,
        output: Int,
        reasoning: Int) -> TokenCount
    {
        TokenCount(
            model: model,
            input: input - min(input, cached) - min(max(0, input - cached), cacheWrite),
            output: output,
            cacheRead: min(input, cached),
            cacheWrite: min(max(0, input - cached), cacheWrite),
            reasoning: reasoning)
    }

    private static func sum(_ values: Int...) -> Int {
        values.reduce(0) { total, value in
            let (result, overflow) = total.addingReportingOverflow(value)
            return overflow ? Int.max : result
        }
    }
}
