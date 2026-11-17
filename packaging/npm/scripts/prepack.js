#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant
//
// Copies the release binary into the package so `npm install` needs no network
// beyond the registry itself — the same promise the app makes.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..", "..");
const source = path.join(root, ".build", "release", "trailwarden-mcp");
const targetDir = path.join(__dirname, "..", "vendor");
const target = path.join(targetDir, "trailwarden-mcp");

if (!fs.existsSync(source)) {
  console.error("prepack: run `swift build -c release --product trailwarden-mcp` first.");
  process.exit(1);
}

fs.mkdirSync(targetDir, { recursive: true });
fs.copyFileSync(source, target);
fs.chmodSync(target, 0o755);
console.log(`prepack: ${path.relative(root, target)} ready`);
