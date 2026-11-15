// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// The one small document Trailwarden reads from the network, and only when the
/// reader asks for it: a version number, a sentence of release notes and a link.
///
/// The app's promise is that it does not go online on its own. This type holds no
/// network code — it turns bytes into a decision — so the promise stays checkable
/// by reading `Sources/TrailwardenCore`.
public struct UpdateFeed: Decodable, Equatable, Sendable {
    public let version: String
    public let notes: String?
    public let url: URL?

    public init(version: String, notes: String? = nil, url: URL? = nil) {
        self.version = version
        self.notes = notes
        self.url = url
    }

    /// Unknown fields are ignored; a missing version is an error, because a feed
    /// without one cannot answer the only question it is asked.
    public static func decode(_ data: Data) throws -> UpdateFeed {
        try JSONDecoder().decode(UpdateFeed.self, from: data)
    }

    /// Component-wise numeric comparison, so 0.10.0 is newer than 0.9.1 (a string
    /// comparison would say the opposite). A leading "v" is tolerated, and a
    /// shorter version is padded with zeros: 1.0 equals 1.0.0.
    public func isNewer(than current: String) -> Bool {
        let published = Self.components(of: version)
        let installed = Self.components(of: current)
        let width = max(published.count, installed.count)
        for index in 0 ..< width {
            let left = index < published.count ? published[index] : 0
            let right = index < installed.count ? installed[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    static func components(of version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }
}
