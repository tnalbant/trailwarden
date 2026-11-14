// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import XCTest
@testable import TrailwardenCore

final class TrailwardenVersionTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(TrailwardenVersion.current.isEmpty)
    }

    func testSchemaVersionIsStable() {
        XCTAssertEqual(TrailwardenVersion.schema, 1)
    }
}
