#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant
//
// Puts the release's own MCP binary into the package, so `npm install` needs no
// network beyond the registry itself and installs the same file the release
// tarball carries: universal (arm64 + x86_64), signed with the Developer ID and
// notarized. scripts/release.sh leaves it in $OUT/signed/.
//
// TRAILWARDEN_RELEASE_OUT   where release.sh wrote (default ~/dev/.trailwarden-release)
// TRAILWARDEN_ALLOW_UNSIGNED=1   use a local universal build instead (testing only)
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..", "..", "..");
const packageDir = path.join(__dirname, "..");
const version = require(path.join(packageDir, "package.json")).version;
const releaseOut = process.env.TRAILWARDEN_RELEASE_OUT || path.join(os.homedir(), "dev", ".trailwarden-release");
const allowUnsigned = process.env.TRAILWARDEN_ALLOW_UNSIGNED === "1";

function fail(message) {
  console.error(`prepack: ${message}`);
  process.exit(1);
}

function signingTeam(file) {
  // codesign prints its details on stderr; an ad-hoc signature has no team.
  try {
    execFileSync("codesign", ["-dv", file], { stdio: ["ignore", "ignore", "pipe"] });
  } catch (error) {
    return null;
  }
  const details = execFileSync("sh", ["-c", 'codesign -dv "$1" 2>&1', "sh", file], { encoding: "utf8" });
  const match = details.match(/^TeamIdentifier=(\S+)$/m);
  return match && match[1] !== "not" ? match[1] : null;
}

let source = path.join(releaseOut, "signed", "trailwarden-mcp");
if (!fs.existsSync(source)) {
  if (!allowUnsigned) {
    fail(`${source} is missing. Run scripts/release.sh first (TRAILWARDEN_ALLOW_UNSIGNED=1 to test with a local build).`);
  }
  const build = ["build", "-c", "release", "--arch", "arm64", "--arch", "x86_64"];
  source = path.join(execFileSync("swift", [...build, "--show-bin-path"], { cwd: root, encoding: "utf8" }).trim(), "trailwarden-mcp");
  if (!fs.existsSync(source)) fail("run `swift build -c release --arch arm64 --arch x86_64 --product trailwarden-mcp` first.");
}

const archs = execFileSync("lipo", ["-archs", source], { encoding: "utf8" }).trim().split(/\s+/);
if (!archs.includes("arm64") || !archs.includes("x86_64")) fail(`${source} is ${archs.join(" ")}, not universal.`);

const team = signingTeam(source);
if (!team && !allowUnsigned) fail(`${source} is not signed with a Developer ID.`);

// The MCP server prints its version on stderr and exits when stdin closes.
const run = spawnSync(source, ["--version"], { input: "", encoding: "utf8", timeout: 10000 });
const reported = `${run.stdout || ""}${run.stderr || ""}`.trim();
if (!reported.includes(version)) fail(`${source} reports "${reported}", package.json says ${version}.`);

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

console.log(
  `prepack: trailwarden-mcp ${version} (${archs.join(" + ")}, ${team ? `team ${team}` : "UNSIGNED"}), LICENSE, Acknowledgements.txt ready`
);
