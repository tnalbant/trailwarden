# Security policy

**English** · [Türkçe](SECURITY.tr.md)

Trailwarden reads local agent transcripts and builds an audit index on the same
machine. Nothing about your agents leaves it. All network calls live in one
file, `Sources/TrailwardenApp/Update/UpdateChecker.swift`. The first is the
update check: a GET for one small JSON file, when you click "Check for updates"
or on the weekly/monthly schedule you can turn on (off by default). The second
is a GET, only when you click "Update prices", for the public `prices.json` in
the repository, used for the API cost estimate (no schedule). CI fails if
`URLSession`, `NSURLConnection`, `URLRequest`, `CFNetwork` or `import Network`
appears in any other file under `Sources/`.

## Reporting a vulnerability

Please open a private security advisory on GitHub
(`Security` → `Advisories` → `Report a vulnerability`) instead of a public
issue. Include the version from `trailwarden --version`, the macOS version, and
a minimal reproduction. We aim to answer within seven days.

In scope:

- redaction bypasses: a secret that reaches the database, an export or a log
- path traversal or file overwrite through `--out`, rules or preferences files
- the database being created world-readable, or an export written without 0600
- prompts, commands or file contents appearing in a file outside the index
- any data other than the update and price-list requests leaving the machine

Out of scope:

- the agents' own transcript files (they are not ours to protect)
- anything requiring an attacker who already has your user account

## Data location and permissions

- index: `~/Library/Application Support/Trailwarden/trailwarden.sqlite` (0600)
- rule preferences: `~/Library/Application Support/Trailwarden/rule-preferences.json` (0600)
- exports: wherever you save them, written atomically with 0600
- no telemetry, no crash reporting, no account; update and price-list checks
  only as above
