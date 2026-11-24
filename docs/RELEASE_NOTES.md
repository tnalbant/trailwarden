<!-- SPDX-License-Identifier: Apache-2.0 -->
# Trailwarden 0.2.5

Fewer false alarms, an interface that reads plainly and can be made larger, and the app starts when you log in if you want it to.

## New

- **Launch at login.** A switch in the first-run screen and in Settings. If macOS refuses (a copy run from Downloads, say), the reason shows in Settings and as a strip in the panel, instead of the switch silently snapping back.
- **Text size.** Settings › Text size: Standard, Large or Larger. The panel grows with it (340, 380 or 420 pt wide).
- **Plain rows, and "Show technical details".** Rows, the panel and notifications now say what happened in a sentence, with no rule ids or raw tool names. Turn on "Show technical details" in Settings, under Text size, to get them back, along with the regex, the session id, the raw JSON and the token breakdown.
- **Rule examples.** With technical details off, each rule in the Rules tab shows commands it flags and commands it leaves alone.
- **28 rules.** R28 warns on a risky database or deploy command.
- **Keyboard in the timeline.** Click a row, then ↑/↓ moves the selection (and loads more at the end), ⏎ moves to the detail pane, Esc comes back, ⌘C copies the command.
- **VoiceOver.** A row is read as one sentence: severity, summary, agent, time. Pickers announce their names and the active tab says "selected".

## Fixed

- **Fewer false alarms.** Measured on the synthetic corpus in the repository (`Tests/TrailwardenCoreTests/Fixtures/rules-corpus`): harmless shell commands flagged went from 73 of 427 to 52 of 430, and those flagged critical from 36 to 15. Risky commands caught went from 160 of 216 to 198 of 241 (25 risky commands were added to the corpus; all are caught). The CI test now holds these numbers, so they cannot slip back unnoticed.
- **Tool output and descriptions are no longer scanned.** A command's result, or the sentence an agent wrote about it, could trigger a rule that the command itself did not.
- **Wrapped commands are checked.** `bash -c "…"` (quoted or not), `env …` and `VAR=… command` were passed over; the command inside is now looked at. Codex's `["bash", "-lc", "…"]` calls are stored as the script they run.
- **Secret files.** Reading a private key or a credentials file is flagged whatever the command (an upload with `aws s3 cp`, `gsutil`, `rclone` or `gh gist`, `tee`, `mv`, `jq`, `gpg`, `7z`, a `docker -v` mount, a path handed to `xargs`, or `cd ~/.aws && cat credentials`), except commands that cannot read a file's content, such as `ls`, `stat`, `chmod` or `test`.
- **Your history is re-checked after the update.** The first start after an update that changed the built-in rules re-runs them over the whole index once (the app, `trailwarden scan` and the MCP server), with your rule settings and mutes. The index moves to schema 8.
- **Kept severities.** `kubectl delete pvc …` and `kubectl delete deployment.apps/…` stay critical, `find ~/Documents -delete` and `find /Users/demo -delete` are flagged, and so is `git push --force origin HEAD`.
- **Launch at login, unticked in the first-run screen,** no longer shows "Could not change the login item" for an app that was never registered.
- **Contrast.** Every text role is at least 4.5:1 (AA) on both backgrounds, in light and dark. Small links, timestamps and critical counts were the weak spots.
- **Untranslated strings.** Text that stayed in English in the other five languages is translated.
- **Deep links open the event.** A click on a row in Today or in the panel opens the timeline on that event, selected and scrolled into view, even when it is several pages down.
- **Panel and Rules tab.** The version moved into the places list, and the update row appears only when there is something to say. The Rules tab re-runs the rules on opening only when a rule or a mute changed.
- **Wording.** "Other sessions on this file" and "No other session touched it" now agree; a price that could not be saved is reported in a plain sentence, with the raw error only under technical details.
- **A Swift 6 isolation error** that only the app build caught, and the app is now built in CI.

## Before publishing, check on a Mac

None of this can run in CI. Go through it once on a real Mac.

- **Launch at login.** Toggle it in onboarding and in Settings. Untick it in onboarding on a fresh install: no failure strip appears. Run the app once from ~/Downloads (not /Applications) and confirm the failure text appears in Settings and as a strip in the panel. With "Show technical details" on, the raw error is appended.
- **Deep links.** Click a row in Today and in the menu bar panel. The timeline opens on that event, selected and scrolled into view, also for an event several pages down.
- **Text size.** Settings › Text size = Larger. Check the menu bar panel (420 pt wide), the timeline, Today, Usage, Rules (the severity picker) and Settings (the 120 pt control near the agent folders): nothing clipped or overlapping. Also the main window at its minimum width (960) at Larger.
- **Contrast.** In light and dark mode, small links (Copy, Mute, Reapply), timestamps and critical counts are readable.
- **Technical details.** Off: no rule ids (R12) or raw tool names in rows, panel or notifications. On: the raw tool name, rule id, regex, session id, raw JSON and token breakdown are all reachable.
- **VoiceOver.** A panel row and a timeline row are read as one sentence (severity, summary, agent, time). Pickers announce their names. The active tab announces "selected".
- **Keyboard.** Click a timeline row, then ↑/↓ moves the selection (loads more at the end), ⏎ moves focus to the detail pane, Esc returns to the list, ⌘C copies the selected command.

# Trailwarden 0.2.4

Usage now estimates what your tokens would cost at API prices, the app has its own icon, and secrets that slipped past the masking are caught.

## New

- **API cost estimate.** The Usage tab splits tokens by model and shows an "API equivalent": what the same tokens would have cost on each provider's pay-as-you-go API. It is an estimate, not a bill; a subscription costs what you pay for it. Prices are built into the release, "Update prices" in Settings › Prices reads a newer public list from this repository on request (the only network read besides the update check), and a price you enter, or mark as free, always wins.
- **An icon of its own.** A shield with a T on it, in the Dock and in the menu bar.

## Fixed

- **A private key cut off in a preview was stored in clear.** Previews are capped at 500 characters before masking, so `cat ~/.ssh/id_rsa` kept the key's first lines without its footer, and the key rule needed both ends. A key header now masks everything after it when the footer is missing.
- **More secret shapes are masked:** Google API keys (`AIza…`, which rule R27 already flagged), GitLab, Stripe, npm and Hugging Face tokens, JSON Web Tokens, `"Authorization": "Bearer …"` inside JSON, and a password inside a URL (`https://user:secret@host`). The "this looks like a path" exception for long runs of letters and slashes is stricter, so a base64 credential that happens to contain slashes is masked.
- **Dodging a rule with a heredoc.** `cat <<'EOF' | bash` and `python3 - <<'EOF'` had their script treated as file content and never checked. A heredoc that is piped into, or fed to, a shell or an interpreter is checked like any command.
- **The MCP server** crashed on `limit: -1` for `list_sessions`, and `search_events` read `-1` as "no limit". Page sizes are kept between 1 and 200.
- **The search index grew on every re-read** and could still match text that had been replaced. Rewritten events now update their search entry; the first launch rebuilds the index once (schema 6).
- **`trailwarden doctor`** reported every index as unhealthy (it expected schema 4).
- **Crashes on odd input:** a rule listed twice in `rule-preferences.json`, or an out-of-range number in Hermes, opencode or Cursor data, no longer stops the app or the scan.
- **Exports** shorten home paths in previews too and mask the branch name; export, preference and index files are private (0600) from the first byte. A busy agent database is reported instead of being read halfway.
- **Hermes** sessions that began before the last scan keep their folder and their token count.
- The first-run screen no longer says Trailwarden has no network access; it names the optional update check.
- **Token totals** from a corrupt agent database (counts near the 64-bit limit) no longer crash the app; sums stop at the largest number instead.
- **A password with `@` or `/` inside a URL** (a database URL whose password is `p@ss`, say) is now masked whole; part of it used to stay visible.
- **SQL fed to a database shell in a heredoc** (`psql`, `mysql`, `sqlite3`, `duckdb`, `mongosh`, `redis-cli` and others, before the `<<` or piped after it) is checked, so `DROP TABLE` inside it is flagged. The same goes for `eval`, `source`, `csh`, `tclsh` and `pwsh`.
- On a hidden app (⌘H) the Dock tile stays, and Settings no longer says notifications are "turned off" before anyone has been asked.

# Trailwarden 0.2.3

One window instead of six, one panel row instead of nine controls, and the interface finally speaks the language of the Mac it runs on.

## New

- **One window, tabs.** Today, Timeline, Report, Usage and Rules are tabs of the dashboard, with Settings behind a divider. ⌘1…⌘5 jump between them, ⌘, still opens Settings, ⌘R scans. The Window menu no longer lists a window per screen.
- **A shorter panel.** The row of nine controls under the menu bar panel became two buttons and a menu that unfolds inside the panel: Report, Usage, Rules, Settings, check for updates, quit.

## Fixed

- **Mixed languages.** Rule sentences came from `rules.json` in Turkish and were shown as stored, so an English window carried Turkish rules. They are resolved in the interface language when drawn; the stored text is only the fallback for a hand-written rule.
- **System menus.** The app declared no supported languages, so Window and Help stayed English on a Turkish Mac. It now lists all six, and Düzen/Görüntü/Pencere/Yardım appear where they should.
- **Notification permission.** The live guard could only ask on the first alert, and Settings could only report that notifications were off. Both ask now, Settings offers the System Settings link when the answer was no, and a grant made there is picked up without a restart.
- **The Dock tile.** Closing the last window left the app in the Dock with nothing to show for it, because the policy was computed while the closing window still counted as visible. A Dock click now brings the dashboard back, and the tile goes away with the last window.
- **The first scan shows its progress** ("Scanning… 42%") in the panel, the first-run screen and the window, and `trailwarden scan` prints a progress line on a terminal.
- **The npm package carries the signed, notarized MCP binary** from the release instead of a local build.

# Trailwarden 0.2.2

The command line tool and the MCP server now run on Intel Macs too, the downloadable binaries are signed and notarized, and the disk image opens with an Applications shortcut.

## Fixed

- **Intel Macs.** The npm package said it supported Intel but carried an Apple Silicon binary only ("Bad CPU type in executable"). The CLI and the MCP server are now universal (arm64 + x86_64) in the release tarball and on npm. The tarball is renamed `trailwarden-<version>-macos-universal.tar.gz`.
- **Signed command line binaries.** The tarball's `trailwarden` and `trailwarden-mcp` were ad-hoc signed, so a browser download was blocked by Gatekeeper. They are signed with the Developer ID and notarized.
- **Licenses in the npm package.** It now carries `LICENSE` and `Acknowledgements.txt` (the Zstandard decoder's BSD notice).
- **Disk image.** It opens with an `/Applications` link next to the app, so installing is one drag.
- **Homebrew.** The cask quits the menu bar app before an upgrade or uninstall, so `brew upgrade` no longer replaces a running app. Install with `brew tap tnalbant/trailwarden`, then `brew install --cask trailwarden` or `brew install trailwarden-cli`.
- **`TRAILWARDEN_DB`** now applies to the CLI and the MCP server as well as the app, so a trial run never writes into your real index.

# Trailwarden 0.2.1

The command line tool and the MCP server now carry their rules inside the binary, so the Homebrew, release-tarball, npm and `make install` builds work on their own.

Everything new in 0.2.0 is listed below.

## Fixed

- `trailwarden` and `trailwarden-mcp` installed without the app stopped with "unable to find bundle named Trailwarden_TrailwardenCore" the first time they checked a rule: the rules lived in a resource bundle that only the app carried. They are compiled in now (`scripts/embed-rules.py`), and a test keeps them identical to `rules.json`.
- The Homebrew formula asks for Xcode 16, which the Swift 6 package needs.

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
