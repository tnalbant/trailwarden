// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

public enum AuditFormat: String, Sendable, CaseIterable, Identifiable {
    case markdown
    case json

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        }
    }

    public var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        }
    }
}

public struct ExportOutcome: Sendable, Equatable {
    public let url: URL
    public let bytes: Int
    public let sessions: Int
    public let events: Int
    public let findings: Int
    public let critical: Int
    public let duration: TimeInterval
}

/// The one place an audit record is rendered and written, so the CLI and the app
/// cannot drift apart. Files are written atomically with mode 600.
public enum ExportWriter {
    public static func data(
        format: AuditFormat,
        sessions: [SessionSummary],
        events: [Event],
        selection: AuditSelection,
        redactor: Redactor
    ) throws -> Data {
        switch format {
        case .json:
            return try JSONReport.data(
                sessions: sessions,
                events: events,
                selection: selection,
                redactor: redactor
            )
        case .markdown:
            // The record lists findings only, so only those need masking; running
            // 24k clean events through eight regexes was most of the export time.
            let body = MarkdownReport.render(
                sessions: sessions,
                events: events.map { $0.risk.isEmpty ? $0 : redactor.redactForExport($0) },
                selection: selection
            )
            return Data(body.utf8)
        }
    }

    @discardableResult
    public static func write(
        format: AuditFormat,
        sessions: [SessionSummary],
        events: [Event],
        selection: AuditSelection,
        redactor: Redactor = Redactor(),
        to url: URL
    ) throws -> ExportOutcome {
        let started = Date()
        let body = try data(
            format: format,
            sessions: sessions,
            events: events,
            selection: selection,
            redactor: redactor
        )

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try body.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let summary = AuditReport.summarize(sessions: sessions, events: events)
        return ExportOutcome(
            url: url,
            bytes: body.count,
            sessions: sessions.count,
            events: summary.events,
            findings: summary.findings,
            critical: summary.critical,
            duration: Date().timeIntervalSince(started)
        )
    }

    /// `trailwarden-2026-11-14.md`
    public static func suggestedFilename(format: AuditFormat, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "trailwarden-\(formatter.string(from: date)).\(format.fileExtension)"
    }
}
