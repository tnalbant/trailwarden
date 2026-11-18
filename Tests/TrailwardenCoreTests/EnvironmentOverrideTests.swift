// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

@testable import TrailwardenCore
import XCTest

/// `TRAILWARDEN_DB` is what keeps a trial run (a demo, a reviewer's scan) out of
/// the real index. The app, the CLI and the MCP server all go through
/// `EventStore.environmentOverride`; if it stopped working, they would quietly
/// write into ~/Library/Application Support/Trailwarden again.
final class EnvironmentOverrideTests: XCTestCase {
    private var saved: String?

    override func setUp() {
        saved = ProcessInfo.processInfo.environment["TRAILWARDEN_DB"]
    }

    override func tearDown() {
        if let saved {
            setenv("TRAILWARDEN_DB", saved, 1)
        } else {
            unsetenv("TRAILWARDEN_DB")
        }
    }

    func testTheVariablePointsAtAnotherIndex() {
        setenv("TRAILWARDEN_DB", "/tmp/trial/index.sqlite", 1)
        XCTAssertEqual(EventStore.environmentOverride?.path, "/tmp/trial/index.sqlite")
    }

    func testATildeIsTheHomeFolder() {
        setenv("TRAILWARDEN_DB", "~/trial.sqlite", 1)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(EventStore.environmentOverride?.path, home + "/trial.sqlite")
    }

    func testUnsetOrEmptyMeansTheRealIndex() {
        unsetenv("TRAILWARDEN_DB")
        XCTAssertNil(EventStore.environmentOverride)
        setenv("TRAILWARDEN_DB", "", 1)
        XCTAssertNil(EventStore.environmentOverride, "an empty value must not become the current directory")
    }

    func testAStoreOpensWhereTheVariablePoints() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("override-\(UUID().uuidString).sqlite").path
        setenv("TRAILWARDEN_DB", path, 1)
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try EventStore(url: XCTUnwrap(EventStore.environmentOverride))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}
