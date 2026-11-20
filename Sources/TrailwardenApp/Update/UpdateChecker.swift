// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation
import TrailwardenCore
import UserNotifications

/// The only file in the app that talks to the network. It goes online when the
/// reader clicks "Check for updates", or — only if the reader picked a schedule
/// in Settings (off by default) — at most once a week or once a month; and when
/// the reader clicks "Update prices", which reads the published price list and
/// has no schedule at all. Nothing is sent either way: each request carries no
/// identifiers, no cursor and no usage data — it is a GET for one small public
/// JSON document.
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

    /// The price list kept in the repository, next to the code it prices. It is
    /// updated there between releases; the app reads it only on request.
    static let publishedPrices = URL(
        string: "https://raw.githubusercontent.com/tnalbant/trailwarden/main/prices.json")!

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

    private var pricesURL: URL {
        #if DEBUG
            if let override = ProcessInfo.processInfo.environment["TRAILWARDEN_PRICES_FEED"],
               let url = URL(string: override)
            {
                return url
            }
        #endif
        return Self.publishedPrices
    }

    /// The published price list, as bytes; checking and keeping it is the
    /// price table's job.
    func downloadPriceList() async throws -> Data {
        try await fetch(pricesURL)
    }

    /// When the feed was last read successfully, by hand or on schedule.
    @Published private(set) var lastCheck: Date?
    private var timer: Timer?

    init() {
        lastCheck = UserDefaults.standard.object(forKey: UpdateSchedule.lastCheckKey) as? Date
    }

    static var schedule: UpdateSchedule {
        UpdateSchedule(rawValue: UserDefaults.standard.string(forKey: UpdateSchedule.storageKey) ?? "") ??
            .never
    }

    /// Starts the schedule the reader picked. With `never` (the default) this
    /// does nothing at all: no timer, no request. The timer only wakes every few
    /// hours to ask "is a check due?", which is a date comparison, not a request.
    func startSchedule() {
        timer?.invalidate()
        timer = nil
        guard Self.schedule != .never else { return }
        Task { await runIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runIfDue() }
        }
    }

    func runIfDue(now: Date = Date()) async {
        guard Self.schedule.isDue(lastCheck: lastCheck, now: now), state != .checking else { return }
        await check(automatic: true)
    }

    /// - Parameter automatic: a scheduled check stays quiet when it fails (the
    ///   reader did not ask, so an offline Mac is not news) and announces a new
    ///   version once with a notification.
    func check(current: String = TrailwardenVersion.installed, automatic: Bool = false) async {
        let previous = state
        state = .checking
        do {
            let data = try await fetch(feedURL)
            let feed = try UpdateFeed.decode(data)
            let newer = feed.isNewer(than: current)
            state = newer ? .available(feed) : .upToDate
            let now = Date()
            lastCheck = now
            UserDefaults.standard.set(now, forKey: UpdateSchedule.lastCheckKey)
            if automatic, newer {
                announce(feed)
            }
        } catch {
            state = automatic ? previous : .failed
        }
    }

    /// One notification per published version, however often the schedule runs.
    private func announce(_ feed: UpdateFeed) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UpdateSchedule.notifiedVersionKey) != feed.version else { return }
        defaults.set(feed.version, forKey: UpdateSchedule.notifiedVersionKey)
        let content = UNMutableNotificationContent()
        content.title = Lf(.updateNotificationTitle, [feed.version])
        content.body = feed.notes ?? ""
        if let url = feed.url {
            content.userInfo = ["url": url.absoluteString]
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "update-\(feed.version)", content: content, trigger: nil))
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
