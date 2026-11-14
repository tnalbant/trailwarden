// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailkeepCore

final class TrailkeepVersionTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(TrailkeepVersion.current.isEmpty)
    }

    func testSchemaVersionIsStable() {
        XCTAssertEqual(TrailkeepVersion.schema, 1)
    }
}
