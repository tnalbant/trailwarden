// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore

/// The only file in the app that talks to the network, and it does so once, when
/// the reader clicks "Check for updates". Nothing runs on launch, nothing runs on
/// a timer, and nothing is sent: the request carries no identifiers, no cursor and
/// no usage data — it is a GET for one small JSON document.
///
/// `THREATMODEL.md` documents this as the single exception; CI allows the network
/// APIs here and nowhere else in `Sources/`.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateFeed)
        case failed
    }

    /// Where the published feed lives: an asset named `latest.json` on the newest
    /// GitHub release. The `releases/latest/download/` path is GitHub's stable
    /// redirect to that asset, so publishing a release is the whole update —
    /// there is no other place to keep in sync.
    ///
    /// Kept as a constant rather than a setting so that a build cannot be talked
    /// into reading somewhere else at runtime.
    static let publishedFeed = URL(
        string: "https://github.com/tnalbant/trailwarden/releases/latest/download/latest.json")!

    @Published private(set) var state: State = .idle

    /// A file URL is accepted in debug builds so the check can be exercised without
    /// a network at all — which is also how it is verified before a release.
    private var feedURL: URL {
        #if DEBUG
            if let override = ProcessInfo.processInfo.environment["TRAILWARDEN_UPDATE_FEED"],
               let url = URL(string: override)
            {
                return url
            }
        #endif
        return Self.publishedFeed
    }

    func check(current: String = TrailwardenVersion.installed) async {
        state = .checking
        do {
            let data = try await fetch(feedURL)
            let feed = try UpdateFeed.decode(data)
            state = feed.isNewer(than: current) ? .available(feed) : .upToDate
        } catch {
            state = .failed
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // No cookies, no credentials: the feed is public and the request should
        // look like what it is — one anonymous read of one file.
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
