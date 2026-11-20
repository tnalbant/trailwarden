// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// What the rules screen persists: per rule, whether it is on and how loud it is.
/// Storing preferences instead of whole rules means a user file cannot pin a stale
/// pattern that a later release fixed.
public struct RulePreference: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var enabled: Bool
    public var severity: Severity

    public init(id: String, enabled: Bool, severity: Severity) {
        self.id = id
        self.enabled = enabled
        self.severity = severity
    }

    enum CodingKeys: String, CodingKey {
        case id = "rule_id"
        case enabled
        case severity
    }
}

public enum RulePreferences {
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        return base
            .appendingPathComponent("Trailwarden", isDirectory: true)
            .appendingPathComponent("rule-preferences.json")
    }

    public static func load(from url: URL) throws -> [RulePreference] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([RulePreference].self, from: data)
    }

    public static func save(_ preferences: [RulePreference], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences.sorted { $0.id < $1.id })
        try PrivateFile.write(data, to: url)
    }

    /// Built-in rules with the stored preferences applied. Rules the file does not
    /// mention keep their shipped values, and unknown ids in the file are ignored.
    public static func apply(_ preferences: [RulePreference], to rules: [Rule]) -> [Rule] {
        // A hand-edited file may list a rule twice; the last entry wins instead of
        // crashing every launch.
        let byId = Dictionary(preferences.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return rules.map { rule in
            guard let preference = byId[rule.id] else { return rule }
            return rule.with(enabled: preference.enabled, severity: preference.severity)
        }
    }

    /// The preferences that describe a rule list, for writing back after an edit.
    public static func preferences(from rules: [Rule]) -> [RulePreference] {
        rules.map { RulePreference(id: $0.id, enabled: $0.isEnabled, severity: $0.severity) }
    }
}

public extension Rule {
    func with(enabled: Bool, severity: Severity) -> Rule {
        Rule(
            id: id,
            title: title,
            severity: severity,
            match: match,
            message: message,
            enabled: enabled)
    }
}
