// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailkeepCore

// The stdio MCP server (four tools: sessions, events, audit, rules) is built on
// top of TrailkeepCore. Until it exists, refuse loudly instead of pretending to
// speak JSON-RPC.
FileHandle.standardError.write(
    Data("trailkeep-mcp \(TrailkeepVersion.current): MCP server not implemented yet.\n".utf8)
)
exit(1)
