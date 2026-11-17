# Contributing

**English** · [Türkçe](CONTRIBUTING.tr.md)

Thanks for looking. This is a small, opinionated tool, so the fastest way in is
an issue that says what you were doing and what happened.

## Ground rules

- **It stays offline.** No networking code in `Sources/` — CI greps for
  `URLSession`, `URLRequest`, `CFNetwork` and friends and fails the build. A
  feature that needs to phone home is out of scope.
- **No real transcripts.** Tests use hand-written synthetic files under
  `Tests/**/Fixtures/`. Never commit a real `.jsonl`, a real index database or a
  screenshot of your own sessions — CI refuses stray `.jsonl` files, and the
  screenshots in the README come from `scripts/seed-demo.py`.
- **One logical change per pull request.** No drive-by reformatting or dependency
  bumps; the whole third-party budget is one pinned package, plus the vendored
  Zstandard decoder in `Sources/CZstd` (update it only as its README says).
- Every Swift file starts with the SPDX header.

## Building

```bash
swift build --build-tests
swift test
xcodegen generate && open Trailwarden.xcodeproj   # app target
```

## Tests

A change in behaviour needs a test that fails without it — if you cannot make
the suite fail by reverting your change, the test is not evidence. Literal
expected values (`"3 events"`) beat assertions written against the constant
being tested.

## Adding a rule

Rules are the easiest way in. Each one is an entry in
`Sources/TrailwardenCore/Resources/rules.json`:

- `tool` (`Bash`, `Write|Edit`, …), `commandRegex`, `pathGlobs` and
  `excludePathGlobs`; `anyOf` lists alternatives, so one rule can cover "the
  shell appends to `~/.zshrc`" and "the edit tool rewrites `~/.zshrc`".
- Shell patterns start with the shared command-start prefix (line start, after
  `;`, `&&`, `|`, `(`, or behind `sudo`), so `echo 'rm -rf /'` is not a delete.
- Run `python3 scripts/embed-rules.py` afterwards: the rules are compiled into
  the binaries from that file, and a test fails while the two differ.
- Add the words in all six languages in `RuleLocalization+Added.swift`.
- Add rows to `RuleCatalogExpansionTests`: commands that must match **and**
  near-misses that must not. A rule without a negative case is not reviewable.
- Try it on your own history before opening the PR:
  `trailwarden rules apply && trailwarden scan --since 30d`. If it fires on
  ordinary work, it will be switched off on day one.

## Adding an agent

New agents are welcome when their on-disk format can be verified:

- JSONL / one-document-per-session transcripts: implement `AgentParser` and add
  a `ScanRoot` (see `GeminiCLIParser` and `ClaudeCodeParser`).
- SQLite history: implement `DatabaseAgentParser` and add a `DatabaseSource`
  (see `HermesDatabaseParser`, including its watermark read).
- Fixtures must be synthetic, and the parser must tolerate a corrupt line
  instead of aborting the scan.

Please do not ship an adapter for a format you could not run against real output
— a parser that silently produces nothing is worse than one that is missing.
