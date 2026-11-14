// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import PackageDescription

// Dependency policy: exactly one third-party package (Apple's argument parser).
// Everything else (JSONL parsing, rules, SQLite/FTS5, MCP) is written in-tree on
// top of system frameworks, so the audit trail stays inspectable and offline.
let package = Package(
    name: "Trailkeep",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TrailkeepCore", targets: ["TrailkeepCore"]),
        .executable(name: "trailkeep", targets: ["TrailkeepCLI"]),
        .executable(name: "trailkeep-mcp", targets: ["TrailkeepMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0")
    ],
    targets: [
        .target(name: "TrailkeepCore"),
        .executableTarget(
            name: "TrailkeepCLI",
            dependencies: [
                "TrailkeepCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "TrailkeepMCP",
            dependencies: ["TrailkeepCore"]
        ),
        .testTarget(
            name: "TrailkeepCoreTests",
            dependencies: ["TrailkeepCore"]
        ),
    ]
)
