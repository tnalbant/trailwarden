<!-- SPDX-License-Identifier: Apache-2.0 -->

# Trailwarden

**The audit trail for your coding agents.** Trailwarden reads the transcripts that
Claude Code, Codex and Gemini CLI already write to your Mac, turns them into a timeline you
can actually read, flags risky commands (wide `rm -rf`, secret-file access,
`curl … | sh`, force pushes), and exports a redacted audit record you can hand to
someone else.

Nothing leaves the machine: no account, no server, no telemetry, no network code
at all (CI fails if `URLSession` or friends ever show up in `Sources/`).

> Status: **pre-alpha (v0.1.0-dev)**. The plan and the daily progress log live in
> the private project workspace; this repository is the product itself.

## What it does

- **Timeline** — every session, every tool call, grouped by project, with the
  branch and working directory the agent ran in.
- **Risk flags** — a data-driven rule set (10 rules in v1) marks the commands you
  would want to have seen before they ran: destructive deletes, `sudo`,
  credential-file reads, data posted to the network, force pushes.
- **Audit export** — `trailwarden export --md` produces a human-readable, redacted
  record for a date range (API keys, tokens, private keys and long base64 blobs
  are masked; home-directory paths are shortened to `~`).
- **MCP server** — `trailwarden-mcp` speaks JSON-RPC over stdio so other agents can
  query the same data (`trailwarden_sessions`, `trailwarden_events`,
  `trailwarden_audit`, `trailwarden_rules`).

It is a **read-only observer**: Trailwarden does not run agents, does not intercept
them, and does not modify their files. It reads `~/.claude`, `~/.codex` and `~/.gemini` the
same way you would, and keeps its own SQLite index under
`~/Library/Application Support/Trailwarden/`.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+)

## Development

```bash
swift build          # TrailwardenCore, trailwarden (CLI), trailwarden-mcp
swift test
xcodegen generate    # produces Trailwarden.xcodeproj for the menu-bar app
open Trailwarden.xcodeproj
```

The Xcode project is generated, not committed: `project.yml` is the source of
truth. Install XcodeGen with `brew install xcodegen`.

### Layout

```
Sources/TrailwardenCore   parsers, event model, rule engine, store, redaction
Sources/TrailwardenCLI    `trailwarden` command line tool
Sources/TrailwardenMCP    stdio MCP server
Sources/TrailwardenApp    SwiftUI menu-bar app (driven by project.yml)
Tests/                  synthetic fixtures only — real transcripts are never committed
```

## Privacy

Trailwarden is built for people who do not want their agent transcripts uploaded
anywhere. Two rules follow from that and are enforced in CI:

1. No networking code in `Sources/`.
2. No real `.jsonl` transcript in the repository; tests use hand-written
   synthetic fixtures only.

The index database is created with mode `0600`. See `docs/` for the threat model
once v0.1.0 lands.

## License

Apache-2.0. Every source file carries an SPDX header.
