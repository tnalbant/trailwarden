# trailwarden-mcp

Offline audit trail for coding agents, exposed as an MCP server.

Reads the transcripts that Claude Code, Codex, Gemini CLI and Hermes already keep
on disk. **No network code**: nothing leaves the machine, and nothing is uploaded.

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
| `audit_summary` | "how many risky commands this month?" |

The database is written by the Trailwarden app or by `trailwarden scan`
(`brew install tnalbant/trailwarden/trailwarden`).
