<!-- SPDX-License-Identifier: Apache-2.0 -->

# Trailwarden

[![CI](https://github.com/tnalbant/trailwarden/actions/workflows/ci.yml/badge.svg)](https://github.com/tnalbant/trailwarden/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/tnalbant/trailwarden)](https://github.com/tnalbant/trailwarden/releases/latest) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) [![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

**English** · [Türkçe](README.tr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Italiano](README.it.md) · [Français](README.fr.md)

**The audit trail for your coding agents.** Claude Code, Codex, Gemini CLI,
opencode, Cursor, GitHub Copilot and Hermes Agent already write down everything they do on your Mac. Trailwarden reads
those transcripts, tells you the moment an agent runs something risky, shows which
agent touched which file, and turns a month of agent work into one page you can
read — or hand to someone else, redacted.

Nothing about your agents leaves the machine: no account, no server, no
telemetry. The only network call in the app is the update check — one GET for one
small JSON file on the newest GitHub release, made when you click it or, if you
turn it on in Settings, at most weekly or monthly (off by default) — and CI fails
if a network API shows up anywhere else in `Sources/`.

> Status: **v0.2.2** — live guard, 27 rules, agent blame, report card, CI gate.
> Interface in English (US), Turkish, German, Spanish, Italian and French.

![Report card](docs/screenshots/report-light.png)

## Why

An agent that ran 400 commands overnight leaves three things behind: raw `.jsonl`
files, a long chat, and a vague feeling. Trailwarden answers the questions that
feeling is about:

| Question | Where |
|---|---|
| Did an agent just do something I would have stopped? | **Live guard** — a notification within seconds |
| Which agent changed this file, and when? | `trailwarden who <file>` · detail pane · MCP |
| What did my agents do this month? | **Report card** |
| Can CI fail when an agent did something risky? | `trailwarden scan --fail-on critical` |
| What exactly ran, and how do I pick that session up again? | **Timeline** + resume command |

## Screenshots

Light, with the timeline, the filters and the inspector:

![Timeline](docs/screenshots/timeline-light.png)

Dark, on the usage screen:

![Usage](docs/screenshots/usage-dark.png)

Every screenshot is taken against an invented database (`scripts/seed-demo.py`),
so no real project appears in them.

## What it does

- **Live guard** — FSEvents tells Trailwarden the moment an agent appends to its
  transcript; the new lines are parsed, the rules run, and a critical finding
  becomes a macOS notification. Click it and the timeline opens on that event.
  No polling, no daemon, and nothing sent anywhere. The same stream is in the
  terminal: `trailwarden watch`.
- **27 risk rules** — destructive deletes, `curl … | sh`, secret and keychain
  reads, API keys pasted into a command, `--dangerously-skip-permissions`,
  `git commit --no-verify`, launchd/cron persistence, shell-startup and agent
  settings edits, CI workflow edits, `DROP TABLE`, `terraform destroy`, disk
  erase, reverse shells, Gatekeeper/SIP switched off, and an agent deleting its
  own transcripts. Every rule is data in [`rules.json`](Sources/TrailwardenCore/Resources/rules.json)
  and has a table of commands that must and must not match.
- **Agent blame** — `trailwarden who src/App.swift` lists every agent that
  changed, read or ran a command on a file, newest first, with the command to
  resume the session that last changed it. Works on folders too.
- **Report card** — a month of agent work on one page: commands, edits, files
  changed, who did the work, the most-changed files and the findings worth a
  look. "Copy summary" gives you counts and rule names only, safe to paste.
- **Timeline** — every session, every tool call, grouped by project, with the
  branch and working directory the agent ran in.
- **CI gate** — `trailwarden scan --since 1d --fail-on critical` exits 1 when a
  finding at or above the threshold is in the window.
- **Audit export** — `trailwarden export --md` produces a human-readable, redacted
  record for a date range (API keys, tokens, private keys and long base64 blobs
  are masked; home-directory paths are shortened to `~`).
- **Usage** — a 30-day token chart and a per-agent breakdown, from the counters
  the agents already write. No price is printed: the same token costs different
  money depending on plan and model.
- **Resume** — the exact command to carry on from a session (`claude --resume`,
  `codex resume`, `gemini --resume`, `opencode --session`, `hermes --resume`),
  quoted and ready to copy.
- **MCP server** — `trailwarden-mcp` speaks JSON-RPC over stdio so other agents
  can ask the same questions (`search_events`, `list_sessions`, `get_event`,
  `file_history`, `audit_summary`). `file_history` lets an agent check who else
  is working on a file before it edits it.

Codex's newer "code mode" wraps every call in a small JavaScript program;
Trailwarden reads the shell commands and patched files out of it, so the
timeline shows `git push --force`, not `text(await tools.exec_command({cmd:…`.
Codex compresses older sessions to `.jsonl.zst`; Trailwarden reads those too,
with the official Zstandard decoder built in (no extra install), so months of
Codex history are not missing from the timeline.

Agents that keep history in SQLite (Hermes: `~/.hermes/state.db`, opencode:
`~/.local/share/opencode/opencode.db`) are read incrementally through a
watermark, so a scan only parses what is new. Only the history tables are read;
opencode's `credential` table is never opened.

Cursor keeps its agent chats in the editor's state database
(`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`).
Trailwarden reads only the chat and step records in it (`composerData:*`,
`bubbleId:*`) — never the editor settings or sign-in data stored next to them.
GitHub Copilot's agent (the Copilot CLI and the Copilot app) writes one log per
session under `~/.copilot/session-state/<id>/events.jsonl`; that log is read
like any transcript. Copilot Chat inside VS Code is not read yet.

It is a **read-only observer**: Trailwarden does not run agents, does not intercept
them, and does not modify their files. It reads `~/.claude`, `~/.codex`, `~/.gemini`,
`~/.copilot` and the databases above the same way you would, and keeps its own SQLite index under
`~/Library/Application Support/Trailwarden/`.

## Install

```bash
brew trust tnalbant/trailwarden   # once: recent Homebrew asks before using a third-party tap
brew tap tnalbant/trailwarden     # once
```

| Method | Installs |
|---|---|
| `brew install --cask trailwarden` | menu bar app |
| `brew install trailwarden-cli` | CLI + MCP server |
| DMG from [Releases](https://github.com/tnalbant/trailwarden/releases) | menu bar app |
| `npm install -g trailwarden-mcp` | MCP server |
| `git clone … && make install` | CLI + MCP server |

See [docs/INSTALL.md](docs/INSTALL.md) for each method, including how to wire
the MCP server into a client.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) when building from source

## Command line

```bash
trailwarden scan                           # index new transcript lines, list findings
trailwarden watch                          # live: print each finding as it happens
trailwarden who Sources/App.swift          # which agent touched this file
trailwarden scan --since 1d --fail-on warn # CI gate: exit 1 on a warning or worse
trailwarden export --md --since 7d > audit.md
trailwarden rules test "git push --force origin main"
trailwarden rules apply                    # re-run the rules over the whole index
trailwarden doctor
```

Exit codes: `0` clean, `1` findings at or above `--fail-on` (default `critical`),
`2` usage error.

## Try it without your own data

```bash
swift build
python3 scripts/seed-demo.py /tmp/trailwarden-demo.sqlite   # 30 invented days, real rules

# after `xcodegen generate` + an xcodebuild, point the app at the demo index:
TRAILWARDEN_DB=/tmp/trailwarden-demo.sqlite \
  "$(xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Debug \
      -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Trailwarden.app/Contents/MacOS/Trailwarden"
```

The CLI reads the same file: `trailwarden who --db /tmp/trailwarden-demo.sqlite src/router.ts`.

`TRAILWARDEN_DB` points the app at another index — the demo, or a copy taken
for a bug report. The live guard stays off for such an index (it would write your
real transcripts into it) unless `TRAILWARDEN_LIVE=1` is set.

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
Sources/CZstd             vendored Zstandard decompressor (BSD-3-Clause, unmodified)
Sources/TrailwardenCLI    `trailwarden` command line tool
Sources/TrailwardenMCP    stdio MCP server
Sources/TrailwardenApp    SwiftUI menu-bar app (driven by project.yml)
Tests/                  synthetic fixtures only — real transcripts are never committed
```

## Privacy

Trailwarden is built for people who do not want their agent transcripts uploaded
anywhere. Two rules follow from that and are enforced in CI:

1. No networking code in `Sources/` except the update check in
   `Sources/TrailwardenApp/Update/UpdateChecker.swift`, which runs when you click
   it, or on the weekly/monthly schedule you can turn on in Settings (off by
   default). CI enforces both halves: a network API anywhere else fails the build,
   and that file losing its reason to exist fails it too. The live guard uses
   FSEvents (file-change notifications from the kernel) and local notifications;
   neither touches the network.
2. No real `.jsonl` transcript in the repository; tests use hand-written
   synthetic fixtures only.

The index database and every export are written with mode `0600`. The threat
model and the reporting process live in [THREATMODEL.md](THREATMODEL.md) and
[SECURITY.md](SECURITY.md).

## License

Apache-2.0. Every source file carries an SPDX header.

### Third-party software

- [swift-argument-parser](https://github.com/apple/swift-argument-parser)
  (Apache-2.0), command line only.
- [Zstandard](https://github.com/facebook/zstd) v1.5.7, decompressor only,
  Copyright (c) Meta Platforms, Inc. and affiliates, used under the
  BSD-3-Clause license. The license text is in
  [Sources/CZstd/LICENSE](Sources/CZstd/LICENSE) and ships inside the app as
  `Acknowledgements.txt`.
