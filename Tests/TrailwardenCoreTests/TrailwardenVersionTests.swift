// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class TrailwardenVersionTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(TrailwardenVersion.current.isEmpty)
    }

    func testVersionIsTheReleaseBeingBuilt() {
        XCTAssertEqual(TrailwardenVersion.current, "0.3.0")
    }

    func testSchemaVersionIsStable() {
        XCTAssertEqual(TrailwardenVersion.schema, 1)
    }
}
