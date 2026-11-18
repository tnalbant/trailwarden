#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant
//
// Copies the release binary into the package so `npm install` needs no network
// beyond the registry itself — the same promise the app makes. The binary must
// be universal (arm64 + x86_64): package.json accepts Intel Macs too.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const root = path.resolve(__dirname, "..", "..", "..");
const packageDir = path.join(__dirname, "..");
const build = ["-c", "release", "--arch", "arm64", "--arch", "x86_64"];

let binDir;
try {
  binDir = execFileSync("swift", ["build", ...build, "--show-bin-path"], { cwd: root, encoding: "utf8" }).trim();
} catch {
  binDir = "";
}
const source = path.join(binDir, "trailwarden-mcp");
if (!binDir || !fs.existsSync(source)) {
  console.error(
    "prepack: run `swift build -c release --arch arm64 --arch x86_64 --product trailwarden-mcp` first."
  );
  process.exit(1);
}

const archs = execFileSync("lipo", ["-archs", source], { encoding: "utf8" }).trim().split(/\s+/);
if (!archs.includes("arm64") || !archs.includes("x86_64")) {
  console.error(`prepack: ${source} is ${archs.join(" ")}, not universal.`);
  process.exit(1);
}

const vendor = path.join(packageDir, "vendor");
fs.mkdirSync(vendor, { recursive: true });
const target = path.join(vendor, "trailwarden-mcp");
fs.copyFileSync(source, target);
fs.chmodSync(target, 0o755);

// Apache-2.0 for Trailwarden, BSD-3-Clause for the bundled Zstandard decoder:
// both travel with every copy of the binary.
fs.copyFileSync(path.join(root, "LICENSE"), path.join(packageDir, "LICENSE"));
fs.copyFileSync(
  path.join(root, "Sources", "TrailwardenApp", "Resources", "Acknowledgements.txt"),
  path.join(packageDir, "Acknowledgements.txt")
);

console.log(`prepack: ${path.relative(root, target)} (${archs.join(" + ")}), LICENSE, Acknowledgements.txt ready`);
