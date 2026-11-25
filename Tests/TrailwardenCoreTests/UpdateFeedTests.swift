// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

@testable import TrailwardenCore
import XCTest

final class UpdateFeedTests: XCTestCase {
    func testDecodesAVersionWithNotesAndLink() throws {
        let json = #"{"version":"0.2.0","notes":"Search starts at the beginning of a word.","url":"https://example.com/trailwarden-0.2.0.dmg"}"#
        let feed = try UpdateFeed.decode(Data(json.utf8))

        XCTAssertEqual(feed.version, "0.2.0")
        XCTAssertEqual(feed.notes, "Search starts at the beginning of a word.")
        XCTAssertEqual(feed.url?.lastPathComponent, "trailwarden-0.2.0.dmg")
    }

    func testNotesAndLinkAreOptional() throws {
        let feed = try UpdateFeed.decode(Data(#"{"version":"0.2.0"}"#.utf8))

        XCTAssertEqual(feed.version, "0.2.0")
        XCTAssertNil(feed.notes)
        XCTAssertNil(feed.url)
    }

    func testFeedWithoutAVersionIsRejected() {
        // A feed that cannot answer the one question asked of it is an error, not a
        // silent "you are up to date".
        XCTAssertThrowsError(try UpdateFeed.decode(Data(#"{"notes":"hi"}"#.utf8)))
    }

    func testNewerVersionsAreDetected() {
        let feed = UpdateFeed(version: "0.2.0")
        XCTAssertTrue(feed.isNewer(than: "0.1.0"))
        XCTAssertFalse(feed.isNewer(than: "0.2.0"))
        XCTAssertFalse(feed.isNewer(than: "0.10.0"))
    }

    func testComparisonIsNumericNotAlphabetical() {
        // "0.10.0" < "0.9.1" as strings; as versions it is newer.
        XCTAssertTrue(UpdateFeed(version: "0.10.0").isNewer(than: "0.9.1"))
        XCTAssertTrue(UpdateFeed(version: "1.0.0").isNewer(than: "0.99.99"))
    }

    func testShorterVersionsArePaddedWithZeros() {
        XCTAssertFalse(UpdateFeed(version: "1.0").isNewer(than: "1.0.0"))
        XCTAssertTrue(UpdateFeed(version: "1.0.1").isNewer(than: "1.0"))
    }

    func testLeadingVIsTolerated() {
        XCTAssertTrue(UpdateFeed(version: "v0.2.0").isNewer(than: "0.1.0"))
        XCTAssertFalse(UpdateFeed(version: "v0.1.0").isNewer(than: "0.1.0"))
    }
}
