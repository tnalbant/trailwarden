#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant
//
// Thin wrapper: the MCP server is the Swift binary in vendor/. Keeping this file
// tiny means `npm install -g trailwarden-mcp` fetches no dependencies at all.
"use strict";

const { spawn } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");

const binary = path.join(__dirname, "..", "vendor", "trailwarden-mcp");

if (!fs.existsSync(binary)) {
  console.error(
    "trailwarden-mcp: vendor/trailwarden-mcp is missing.\n" +
      "To build from source: git clone https://github.com/tnalbant/trailwarden && make install"
  );
  process.exit(2);
}

const child = spawn(binary, process.argv.slice(2), { stdio: "inherit" });
child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
