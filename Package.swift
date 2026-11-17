// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import PackageDescription

/// Dependency policy: exactly one third-party package (Apple's argument parser).
/// Everything else (JSONL parsing, rules, SQLite/FTS5, MCP) is written in-tree on
/// top of system frameworks, so the audit trail stays inspectable and offline.
/// The one vendored exception is `CZstd`: the official Zstandard decompressor
/// (BSD, Meta), as its single-file build, because macOS ships no zstd decoder
/// and Codex compresses older sessions with it. See Sources/CZstd/README.md.
let package = Package(
    name: "Trailwarden",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TrailwardenCore", targets: ["TrailwardenCore"]),
        .executable(name: "trailwarden", targets: ["TrailwardenCLI"]),
        .executable(name: "trailwarden-mcp", targets: ["TrailwardenMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0")
    ],
    targets: [
        .target(
            name: "CZstd",
            exclude: ["LICENSE", "README.md"]),
        .target(
            name: "TrailwardenCore",
            dependencies: ["CZstd"],
            resources: [.process("Resources")]),
        .executableTarget(
            name: "TrailwardenCLI",
            dependencies: [
                "TrailwardenCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "TrailwardenMCP",
            dependencies: ["TrailwardenCore"]),
        .testTarget(
            name: "TrailwardenCoreTests",
            dependencies: ["TrailwardenCore"],
            // Fixtures are read from disk via #filePath, not bundled as resources.
            exclude: ["Fixtures"])
    ])
