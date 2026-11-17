<!-- SPDX-License-Identifier: Apache-2.0 -->
# Trailwarden 0.2.0

Trailwarden now watches your agents live and tells you within seconds when one runs something risky, shows which agent touched a file, and sums up a month of agent work on one page.

## New

- **Live guard.** FSEvents wakes Trailwarden when an agent appends to its transcript; the new lines are parsed, the rules run, and a critical finding becomes a macOS notification that opens the event when clicked. Settings → Live guard switches it off or widens it to warnings. The panel shows whether it is running. The index stays current without pressing Scan.
- **`trailwarden watch`** — the same live stream in a terminal, as text or one JSON object per finding.
- **Agent blame.** `trailwarden who <file|folder>` lists every agent that changed, read or ran a command on a path, newest first, with the command to resume the session that last changed it. The event detail pane shows the other agents on the same file, and the MCP server has a new `file_history` tool so an agent can check before it edits.
- **Report card.** A month of agent work on one page — commands, edits, files changed, who did the work, the most-changed files and the findings worth a look. It opens after the first scan. "Copy summary" puts counts and rule names on the clipboard, never a command, path or project name.
- **17 new rules (27 in all):** environment files, keychain password reads, launchd/cron persistence, shell startup files, agent settings and hooks, approval bypass flags (`--dangerously-skip-permissions`, `--yolo`), `git --no-verify`, GitHub deletions, package publishing, CI workflow edits, Gatekeeper/SIP/quarantine switched off, reverse shells, disk erase, destructive SQL, infrastructure teardown, an agent deleting transcripts or shell history, and API keys pasted into a command.
- **CI gate.** `trailwarden scan --fail-on critical|warn|info|none`.
- **`trailwarden rules apply`** re-runs the rules over the whole index from the terminal.
- **opencode.** Sessions in `~/.local/share/opencode/opencode.db` are read incrementally like Hermes: shell commands, reads, edits and token counts. Only the history tables are opened, never `credential`.
- **Optional automatic update check.** Settings → Automatic update check: off (default), weekly or monthly. When a new version is found you get one notification per version; clicking it opens the release page. It is still the same single GET for one small JSON file.
- **Cursor and GitHub Copilot.** Cursor's agent chats are read from the editor's state database (only the chat and step records; settings and sign-in data in the same file are never queried), and GitHub Copilot's agent sessions — Copilot CLI and the Copilot app — from `~/.copilot/session-state`. Terminal commands, file reads and edits, and token counts go through the same rules as every other agent. "Agent settings changed" and "Agent history deleted" now know Cursor's, Copilot's and opencode's files. Copilot Chat inside VS Code is not read yet.
- **Compressed Codex history.** Codex compresses older sessions to `.jsonl.zst`, and macOS has no zstd decoder, so those sessions were missing. The official Zstandard decompressor (BSD-3-Clause) is now built in — about 220 KB — and they are read like any other session, with the same event ids if Codex compresses a session after it was indexed.
- `--agent` accepts `gemini`, `hermes`, `opencode`, `cursor` and `copilot`.

## Fixed

- **Codex code mode.** Newer Codex builds wrap every tool call in JavaScript; the command column held that program, so no shell rule could match a Codex command. The real shell commands and patched files are read out of it now.
- **Fewer false alarms.** "Destructive delete" no longer fires on deep paths such as `rm -rf ~/.cache/x/y` or on uninstalling one app; `rm -f` without `-r` is not recursive; `sudo rm -rf /` is caught. "Write outside the project" no longer fires because a command calls `/usr/bin/grep`. `curl … | python3 -c '…'` (reading JSON) is not "download and run". `.env` reads are a warning of their own instead of a critical secret-file hit, and `.env.example` is not a secret. File content written through a heredoc or a patch no longer counts as paths the command touches.
- **Long paths were stored as `[redacted:blob]`.** The base64 mask matched any 64-character run of letters and slashes; paths are recognised and kept.
- Faster first scan of large histories: a multi-megabyte transcript line was searched for its end again on every read, and every secret pattern ran over every raw line; now the search resumes where it stopped and a pattern only runs when its fixed part (`sk-`, `AKIA`, …) is present. Same results, measured on 3.5 GB of Codex history.
- An index upgraded from the first schema could report "database disk image is malformed" on its first update.
- The first launch after updating re-reads every transcript once (schema 5), so older events get the Codex fix, the path fix and the new rules.
- Onboarding showed a Turkish word in every language for a missing folder.
- `latest.json` is built by `scripts/release.sh` and uploaded with every release, so "Check for updates" has something to read.
