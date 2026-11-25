// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import Foundation

public extension PriceTable {
    /// Standard pay-as-you-go rates, USD per million tokens, from each
    /// provider's own pricing page on the date below. Where a provider has tiers,
    /// the default one is used: the short-context rate (OpenAI up to 272K,
    /// Claude Haiku 5.5 up to 100K), the 5-minute (Claude) or 30-minute
    /// (OpenAI) cache write, and DeepSeek's peak-hour rate. A model with no
    /// separate cache-write price is charged its input rate for writes.
    ///
    /// Sources: platform.claude.com/docs/en/about-claude/pricing,
    /// developers.openai.com/api/docs/pricing, aistudio.google.com/docs/pricing,
    /// api-docs.deepseek.com/quick_start/pricing.
    static let builtIn = PriceTable(asOf: "2026-11-20", prices: [
        // Anthropic
        "claude-fable-5-2": ModelPrice(input: 8, output: 40, cacheRead: 0.20, cacheWrite: 10),
        "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25, cacheWrite: 12.50),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20, cacheWrite: 5),
        "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50, cacheWrite: 6.25),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.10, cacheWrite: 2.50),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.50),
        "claude-haiku-5-5": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),

        // OpenAI
        "gpt-6-luna": ModelPrice(input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
        "gpt-6-sol": ModelPrice(input: 2, output: 10, cacheRead: 0.20, cacheWrite: 2.50),
        "gpt-6-astra": ModelPrice(input: 10, output: 50, cacheRead: 1, cacheWrite: 12.50),
        "gpt-6.1-sol": ModelPrice(input: 2, output: 10, cacheRead: 0.10, cacheWrite: 2.50),
        "gpt-6.1-terra": ModelPrice(input: 1, output: 5, cacheRead: 0.05, cacheWrite: 1.25),
        "gpt-5.6-luna": ModelPrice(input: 0.20, output: 1.20, cacheRead: 0.02, cacheWrite: 0.25),
        "gpt-5.6-sol": ModelPrice(input: 4, output: 20, cacheRead: 0.40, cacheWrite: 5),
        "gpt-5.6-terra": ModelPrice(input: 2, output: 12, cacheRead: 0.20, cacheWrite: 2.50),
        "gpt-5.5": ModelPrice(input: 5, output: 30, cacheRead: 0.50, cacheWrite: 5),
        "gpt-5.4": ModelPrice(input: 2.50, output: 15, cacheRead: 0.25, cacheWrite: 2.50),

        // Google
        "gemini-3-flash-preview": ModelPrice(input: 0.50, output: 3, cacheRead: 0.05, cacheWrite: 0.50),
        "gemini-3.1-flash-lite": ModelPrice(input: 0.25, output: 1.50, cacheRead: 0.025, cacheWrite: 0.25),

        // DeepSeek: v4-flash and v4.1-flash are served and billed as deepseek-flash.
        "deepseek-flash": ModelPrice(input: 0.30, output: 1.20, cacheRead: 0.006, cacheWrite: 0.30),
        "deepseek-v4-flash": ModelPrice(input: 0.30, output: 1.20, cacheRead: 0.006, cacheWrite: 0.30),
        "deepseek-v4.1-flash": ModelPrice(input: 0.30, output: 1.20, cacheRead: 0.006, cacheWrite: 0.30),
        "deepseek-v4-pro": ModelPrice(input: 1.32, output: 3.96, cacheRead: 0.044, cacheWrite: 1.32)
    ])
}
