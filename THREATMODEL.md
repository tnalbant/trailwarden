# Threat model

**English** · [Türkçe](THREATMODEL.tr.md)

## What Trailwarden is

A local reader for the transcript files that coding agents already write to
disk. It turns them into an index you can search, shows the risky steps, and
lets you export a redacted record.

## Assumptions

1. The transcripts are already on disk, in the user's home directory, readable
   by the user. Trailwarden does not create that exposure; it reads it.
2. The user owns the machine and the account.
3. Trailwarden runs with the user's privileges. It does not ask for root, does
   not install a privileged helper, and is not a background daemon.

4. The live guard is part of the app process. It asks the kernel (FSEvents)
   which transcript files changed and posts local notifications through the
   user's own Notification Center; it opens no socket and starts no helper.

## What it protects against

- **Leaving the machine.** The app never sends anything about the agents. Exactly one
  file in the codebase makes network calls, `Sources/TrailwardenApp/Update/UpdateChecker.swift`.
  The first is a GET for one small JSON document (`version`, `notes`, `url`), no cookies, no
  identifiers, no query string. It runs when the reader clicks "Check for
  updates", or — only if the reader picks a schedule in Settings, which is off by
  default — at most once a week or once a month. The same file makes one more GET,
  only when the reader clicks "Update prices": the public `prices.json` in the
  project's repository, used for the API cost estimate. It has no schedule; the
  downloaded list must parse, carry a date and hold sane rates before it is kept,
  and it never replaces a price the reader entered. Everything else stays local, and
  CI fails the build if a network API appears in any other file under `Sources/`.
- **Secrets in exports.** Known token shapes are masked before storage and
  again on export; the raw line is masked too. A test asserts every documented
  pattern is caught, and an export test asserts a token never reaches the file.
- **Accidental disclosure in a shared file.** Home paths become `~`, exports
  are 0600, and the JSON contract carries no raw transcript line.
- **Losing the record when an agent cleans up.** Off by default, the archive keeps a
  compressed copy of Claude Code, Codex, Gemini CLI and Copilot transcripts under
  `~/Library/Application Support/Trailwarden/Archive/`. Files are 0600 and folders
  0700. It is append-only: a transcript that is shortened or rewritten keeps its
  earlier copy as a version. It is a copy of what the agents wrote, redacted no
  further, so it holds whatever secrets the transcripts hold; that is why it is
  opt-in. Cursor, opencode and Hermes are not archived.
- **Secrets left in agent settings.** Rule R29 reads `~/.claude/settings*.json`,
  project `.claude/settings*.json`, `~/.codex/config.toml` and `~/.gemini/settings.json`
  read-only, and stores only a redacted preview. A finding is keyed by file, rule
  and a digest of the redacted line, so a secret rotated on the same line keeps the
  same key: a finding you reviewed stays reviewed.
- **Silent rewriting of the record.** Events have stable ids derived from their
  transcript, so re-reading a file replaces the same rows instead of adding or
  dropping any. Rows are removed only by an explicit `prune` or the retention you choose (Forever by default), and rule hits are
  rewritten only when the rules change. Trailwarden does not make the index
  tamper-proof: the owner of the account can edit it like any other file.

## What it does not protect against

- An attacker who already has your account. The index is readable by your user.
- A compromised agent writing false transcripts. Trailwarden records what the
  agent wrote; it cannot verify that the agent was honest.
- Secrets the agents wrote into their own logs before Trailwarden ran. Redaction
  is pattern based: an unusual secret shape can pass through.
- Disk-level attackers (FileVault is the answer there, not this app).

## Trust boundaries

| Boundary | Risk | Mitigation |
|---|---|---|
| transcript files → parser | malformed input | line-level tolerance, a broken file never aborts a scan |
| editor state database → Cursor parser | reading more than the chats (settings, sign-in tokens live in the same file) | opened read-only; the only queries are key-range reads of `composerData:` and `bubbleId:` rows in `cursorDiskKV`; `ItemTable` is never queried, and a test plants a token there to prove it stays unread |
| `.zst` archive → decoder | malformed or hostile compressed data | the official Zstandard decoder (fuzzed upstream), streamed in bounded chunks; a frame asking for a window over 128 MB is refused; a corrupt or truncated file fails that file only |
| parser → database | redaction miss | rules run on raw text, store only ever sees masked text |
| database → export | leaking paths or tokens | second redaction pass, `~` shortening, 0600 |
| rules file → regex engine | catastrophic backtracking | the shipped patterns are anchored and bounded, and every one is exercised by a table of matching and non-matching commands; users can switch rules off or regrade them, not add regexes |
| index → notification | a command shown on the lock screen | the notification carries the already-masked command; macOS hides notification previews on the lock screen by default |
| index → shareable summary | leaking work details | the report card's summary is built from counts, agent names and rule titles only; a test asserts no command, path or project name reaches it |
