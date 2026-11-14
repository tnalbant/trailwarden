# Threat model

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

## What it protects against

- **Leaving the machine.** No network code at all; a CI grep enforces it.
- **Secrets in exports.** Known token shapes are masked before storage and
  again on export; the raw line is masked too. A test asserts every documented
  pattern is caught, and an export test asserts a token never reaches the file.
- **Accidental disclosure in a shared file.** Home paths become `~`, exports
  are 0600, and the JSON contract carries no raw transcript line.
- **Evidence tampering.** The index is append-only from the app's point of
  view: files are re-read only when size or mtime changes, and every event
  keeps its session id and timestamp.

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
| parser → database | redaction miss | rules run on raw text, store only ever sees masked text |
| database → export | leaking paths or tokens | second redaction pass, `~` shortening, 0600 |
| rules file → regex engine | catastrophic backtracking | patterns are anchored and bounded; user rules are validated at load |
