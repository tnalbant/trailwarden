<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installing Trailwarden

**English** · [Türkçe](INSTALL.tr.md)

Every method installs the menu bar app, the command line tools (`trailwarden`,
`trailwarden-mcp`), or both. Nothing about your agents leaves the machine after
installing; the only network call is the optional update check (see
[Privacy](../README.md#privacy)).

| # | Method | Installs | Available |
|---|---|---|---|
| 1 | Homebrew cask (own tap) | App | yes |
| 2 | Homebrew formula (builds from source) | CLI + MCP | yes |
| 3 | DMG (GitHub Releases) | App | yes |
| 4 | npm (`-g`) | MCP server | yes |
| 5 | From source (`make install`) | CLI + MCP | yes |
| 6 | Official `homebrew-cask` | App | after the repository qualifies |

Requirements: macOS 14 (Sonoma) or later. Building from source needs the Xcode
command line tools (Swift 6).

## 1. Homebrew cask (own tap)

```bash
brew trust tnalbant/trailwarden   # once: recent Homebrew asks before using a third-party tap
brew tap tnalbant/trailwarden     # once
brew install --cask trailwarden
```

Downloads the DMG of the newest release, checks its checksum and puts
`Trailwarden.app` in `/Applications`.

## 2. Homebrew formula (CLI + MCP, from source)

```bash
brew install trailwarden-cli      # after the two "once" lines above
```

Needs the Xcode command line tools; compiles with Swift (about a minute).

## 3. DMG (GitHub Releases)

Download `Trailwarden-<version>.dmg` from the
[Releases](https://github.com/tnalbant/trailwarden/releases) page, open it and
drag `Trailwarden.app` into `/Applications`.

A signed and notarized build opens without a Gatekeeper warning. For an
unsigned build: `System Settings → Privacy & Security → Open Anyway`.

## 4. npm (MCP server)

```bash
npm install -g trailwarden-mcp
```

The package carries the compiled Swift binary, so installing needs no network
beyond the npm registry itself.

To add it to an MCP client:

```json
{
  "mcpServers": {
    "trailwarden": {
      "command": "trailwarden-mcp",
      "args": ["--db", "~/Library/Application Support/Trailwarden/trailwarden.sqlite"]
    }
  }
}
```

## 5. From source

```bash
git clone https://github.com/tnalbant/trailwarden.git
cd trailwarden
make install                   # /usr/local/bin (may need sudo)
make install PREFIX=~/.local   # or anywhere on your PATH
```

`make app` builds the menu bar app; `make release` produces the DMG, the CLI
tarball and their SHA-256 checksums.

## 6. Official homebrew-cask

The official repository accepts apps once they are well known (it looks at
stars, forks and watchers). Until then, use the tap above.

---

## Check that it works

```bash
trailwarden doctor          # which agent histories it can read
trailwarden watch           # live: print each finding as it happens
trailwarden who README.md   # which agent touched this file
trailwarden --help
```

On first launch the app shows what it will read. **Scan** indexes the existing
histories and then opens the 30-day report card. From then on the live guard
runs by itself and sends a notification when an agent runs something critical
(Settings → Live guard).

## Uninstall

```bash
brew uninstall --cask trailwarden        # or drag Trailwarden.app to the Trash
brew uninstall trailwarden-cli
make uninstall                           # if installed from source
rm -rf ~/Library/Application\ Support/Trailwarden   # the index; your agents' files are untouched
```
