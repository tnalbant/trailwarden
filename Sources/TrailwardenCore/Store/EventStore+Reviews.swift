// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Review states for findings. A finding with no row is `new`; the key is a
/// `FindingKey`, so a state outlives re-scans and rule re-grades.
public extension EventStore {
    func setReview(_ state: ReviewState, for key: String, at: Date = Date()) throws {
        if state == .new {
            let delete = try database.prepare("DELETE FROM finding_reviews WHERE finding_key = ?")
            try delete.bind([.text(key)])
            try delete.step()
            return
        }
        let statement = try database.prepare("""
        INSERT OR REPLACE INTO finding_reviews (finding_key, state, at) VALUES (?,?,?)
        """)
        try statement.bind([.text(key), .text(state.rawValue), .double(at.timeIntervalSince1970)])
        try statement.step()
    }

    /// The stored state of each key; keys with no row are `new`.
    func reviewStates(for keys: [String]) throws -> [String: ReviewState] {
        var result: [String: ReviewState] = [:]
        let statement = try database.prepare("SELECT state FROM finding_reviews WHERE finding_key = ?")
        for key in Set(keys) {
            try statement.bind([.text(key)])
            if try statement.step(), let raw = statement.text(0), let state = ReviewState(rawValue: raw) {
                result[key] = state
            } else {
                result[key] = .new
            }
        }
        return result
    }

    /// Marks every finding found before `foundBefore` as reviewed, unless it
    /// already has a state. Returns how many findings changed.
    @discardableResult
    func markAllReviewed(foundBefore: Date, at: Date = Date()) throws -> Int {
        let cutoff = foundBefore.timeIntervalSince1970
        var keys: [String] = []

        let events = try database.prepare("SELECT id, risk FROM events WHERE ts < ? AND risk <> '[]'")
        try events.bind([.double(cutoff)])
        let decoder = JSONDecoder()
        while try events.step() {
            guard let id = events.text(0), let json = events.text(1),
                  let hits = try? decoder.decode([RiskHit].self, from: Data(json.utf8))
            else { continue }
            for hit in hits where !hit.allowed {
                keys.append(FindingKey.event(id, rule: hit.ruleId))
            }
        }
        let files = try database.prepare("SELECT finding_key FROM file_findings WHERE found_at < ?")
        try files.bind([.double(cutoff)])
        while try files.step() {
            if let key = files.text(0) {
                keys.append(key)
            }
        }

        var changed = 0
        let existing = try reviewStates(for: keys)
        let insert = try database.prepare("""
        INSERT OR IGNORE INTO finding_reviews (finding_key, state, at) VALUES (?,?,?)
        """)
        try database.transaction {
            for key in Set(keys) where existing[key] == .new {
                try insert.bind([
                    .text(key),
                    .text(ReviewState.reviewed.rawValue),
                    .double(at.timeIntervalSince1970)
                ])
                try insert.step()
                changed += 1
            }
        }
        return changed
    }

    /// Events with at least one active hit that has no review yet, without their
    /// raw JSON. A superset of what the inbox shows per hit: the caller still
    /// checks each (event, rule) key.
    internal func eventsWithUnreviewedFindings() throws -> [Event] {
        let decided = ReviewState.allCases.filter { $0 != .new }.map { "'\($0.rawValue)'" }
            .joined(separator: ",")
        let statement = try database.prepare("""
        SELECT \(Self.eventColumnsWithoutRaw) FROM events
        WHERE events.severity_rank IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM json_each(events.risk) AS hit
            WHERE COALESCE(json_extract(hit.value, '$.allowed'), 0) = 0
              AND NOT EXISTS (
                SELECT 1 FROM finding_reviews AS review
                WHERE review.finding_key = 'event:' || events.id || ':' || json_extract(hit.value, '$.ruleId')
                  AND review.state IN (\(decided))))
        """)
        var result: [Event] = []
        while try statement.step() {
            if let event = Self.event(from: statement) {
                result.append(event)
            }
        }
        return result
    }

    /// Rule id to the number of findings marked false alarm, for tuning hints.
    func falsePositiveCounts() throws -> [String: Int] {
        let statement = try database.prepare("SELECT finding_key FROM finding_reviews WHERE state = ?")
        try statement.bind([.text(ReviewState.falsePositive.rawValue)])
        var counts: [String: Int] = [:]
        while try statement.step() {
            if let key = statement.text(0), let rule = FindingKey.ruleID(of: key) {
                counts[rule, default: 0] += 1
            }
        }
        return counts
    }

    /// Drops reviews of event findings whose event no longer exists, and of file
    /// findings whose row is gone.
    func removeOrphanEventReviews() throws {
        try database.execute("""
        DELETE FROM finding_reviews
        WHERE finding_key LIKE 'file:%'
          AND finding_key NOT IN (SELECT finding_key FROM file_findings)
        """)
        let select = try database
            .prepare("SELECT finding_key FROM finding_reviews WHERE finding_key LIKE 'event:%'")
        var keys: [String] = []
        while try select.step() {
            if let key = select.text(0) {
                keys.append(key)
            }
        }
        let exists = try database.prepare("SELECT 1 FROM events WHERE id = ?")
        let delete = try database.prepare("DELETE FROM finding_reviews WHERE finding_key = ?")
        for key in keys {
            // event:<id>:<rule>; the id may contain ':', the rule never does.
            let body = key.dropFirst("event:".count)
            guard let split = body.lastIndex(of: ":") else { continue }
            try exists.bind([.text(String(body[..<split]))])
            if try !exists.step() {
                try delete.bind([.text(key)])
                try delete.step()
            }
        }
    }
}
