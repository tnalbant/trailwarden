# trailwarden-mcp

Local audit trail for coding agents, exposed as an MCP server (macOS, Apple
Silicon).

Answers questions about what Claude Code, Codex, Gemini CLI, opencode, Cursor,
GitHub Copilot and Hermes did on your Mac, from the index the Trailwarden app or
CLI builds. The MCP server opens no network connection; nothing is uploaded.

## Install

```bash
npm install -g trailwarden-mcp
```

## Wire it into an MCP client

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

## Tools

| Tool | What it answers |
|---|---|
| `search_events` | "which commands touched this file?" |
| `list_sessions` | "what did the agent do yesterday?" |
| `get_event` | "show me that call in full" |
| `file_history` | "which agent changed this file, and when?" |
| `audit_summary` | "how many risky commands this month?" |

The database is written by the Trailwarden app or by `trailwarden scan`
(`brew install --cask tnalbant/trailwarden/trailwarden` or
`brew install tnalbant/trailwarden/trailwarden-cli`).
