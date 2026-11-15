// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Every user-visible string in the interface, as a semantic key.
///
/// The English text is the reference: a translation table that misses a key
/// falls back to English rather than showing a raw identifier, and the tests
/// assert that no table misses one.
public enum UIString: String, CaseIterable, Sendable {
    /// Scope and time
    case today, last7Days, last30Days, allTime, allSessions, scope, projects
    /// Windows and panels
    case windowRules, windowUsage, windowSettings, openDashboard, recentSessions
    /// Activity feed — what the agent did, not how many rows the database holds
    case whatHappened, nothingRiskyToday, todayFeed, timelineTab, messagesToday
    /// Recovery from a filter combination that matches nothing
    case clearFilters
    // Counts
    case events, event, findings, sessions, eventCount, sessionMeta, sessionCritical
    case projectMeta, liveCount, liveTooltip, zeroEvents, eventsRatio
    // Empty states
    case noDataYet, noSessionsFound, noSessionSelected, noEventsInRange, noEventsHint
    case pickEvent, pickEventHint, loadMore
    // Scanning
    case scanning, rescan, scan, startScan, filesCount
    // Severity
    case severityCritical, severityWarning, severityInfo
    // Event detail
    case labelCommand, labelText, labelDiff, labelPaths, labelRaw
    case resumeSession, copy, copied, whyFlagged, muteThirtyDays, muteThirtyDaysHint
    // Rules
    case rulesIntro, disableRule, enableRule, ruleHits, ruleMatchesAll, ruleTool
    case mutedRules, noMutes, removeMute, daysLeft, muteExpired, reapplying, reapply
    // Filters
    case allAgents, onlyFindings, rawStream, showCountersHint
    // Settings
    case appearance, appearanceAutomatic, appearanceLight, appearanceDark, appearanceHint
    case languageSection, languageSystem, languageHint
    case scannedDirs, dirsHint, retention, retentionDays, cleanupNow, retentionHint
    case exportSection, exportAction, exportRange, exportHint
    case privacySection, privacyText, privacyBadge, settingsVersion
    // Usage
    case usageSummary, dailyTokens, noTokenData, token, byAgent, processedTokens
    case counterCount, noCounterData, usageNote
    // Status line
    case statusScan, statusError, statusPrune, statusPruneFailed
    case statusExport, statusExportFailed
    // Onboarding
    case onboardingTitle, onboardingPrivacy
    // Small words
    case axisDay, quit, missingFolder
}

public enum UITranslations {
    public static let english: [UIString: String] = [
        .today: "Today",
        .last7Days: "7 days",
        .last30Days: "30 days",
        .allTime: "All time",
        .allSessions: "All sessions",
        .scope: "Scope",
        .projects: "Projects",

        .windowRules: "Rules",
        .windowUsage: "Usage",
        .windowSettings: "Settings",
        .openDashboard: "Dashboard",
        .recentSessions: "Recent sessions",
        .whatHappened: "What happened",
        .nothingRiskyToday: "Nothing risky today",
        .todayFeed: "Today",
        .timelineTab: "Timeline",
        .messagesToday: "%d messages",
        .clearFilters: "Clear filters",

        .events: "events",
        .event: "event",
        .findings: "findings",
        .sessions: "sessions",
        .eventCount: "%d events",
        .sessionMeta: "%@ · %d events",
        .sessionCritical: "%d critical",
        .projectMeta: "%d sessions · %d events",
        .liveCount: "%d live",
        .liveTooltip: "This session wrote in the last two minutes — the agent may still be running",
        .zeroEvents: "0 events",
        .eventsRatio: "%d / %d events",

        .noDataYet: "No data yet — hit Scan.",
        .noSessionsFound: "No sessions yet.",
        .noSessionSelected: "No session",
        .noEventsInRange: "No events in this range.",
        .noEventsHint: "Widen the time range, clear the filters, or run a new scan.",
        .pickEvent: "Pick an event",
        .pickEventHint: "The command, the paths, the diff and the rule's reasoning open here.",
        .loadMore: "Load more",

        .scanning: "Scanning…",
        .rescan: "Scan again",
        .scan: "Scan",
        .startScan: "Start scanning",
        .filesCount: "%d files",

        .severityCritical: "critical",
        .severityWarning: "warning",
        .severityInfo: "info",

        .labelCommand: "Command",
        .labelText: "Text",
        .labelDiff: "Diff",
        .labelPaths: "Paths",
        .labelRaw: "Raw record (redacted)",
        .resumeSession: "Resume this session",
        .copy: "Copy",
        .copied: "Copied",
        .whyFlagged: "Why it was flagged",
        .muteThirtyDays: "Mute for 30 days",
        .muteThirtyDaysHint: "Stop flagging this for 30 days",

        .rulesIntro: "Turning a rule off, or changing its severity, re-evaluates the index right away — past events are re-flagged under the new setting.",
        .disableRule: "Turn rule off",
        .enableRule: "Turn rule on",
        .ruleHits: "%d events",
        .ruleMatchesAll: "every event",
        .ruleTool: "tool: %@",
        .mutedRules: "Muted",
        .noMutes: "Nothing muted. Open an event and choose 'Mute for 30 days' to add one.",
        .removeMute: "Remove",
        .daysLeft: "%d days",
        .muteExpired: "expired",
        .reapplying: "Re-evaluating the index…",
        .reapply: "Re-evaluate",

        .allAgents: "All agents",
        .onlyFindings: "Findings only",
        .rawStream: "Raw stream",
        .showCountersHint: "Also show token counters and session starts",

        .appearance: "Appearance",
        .appearanceAutomatic: "Automatic",
        .appearanceLight: "Light",
        .appearanceDark: "Dark",
        .appearanceHint: "Automatic follows the macOS light/dark setting.",
        .languageSection: "Language",
        .languageSystem: "System",
        .languageHint: "Interface language. A change applies immediately.",
        .scannedDirs: "Watched folders",
        .dirsHint: "Folders are read from their default locations. Files stay where they are — they are only read.",
        .retention: "Retention",
        .retentionDays: "%d days",
        .cleanupNow: "Clean up now",
        .retentionHint: "Events older than this are dropped from the index. File signatures are kept on purpose, so the next scan does not bring deleted events back.",
        .exportSection: "Export",
        .exportAction: "Export…",
        .exportRange: "Last 30 days",
        .exportHint: "Same content as `trailwarden export` on the command line: redacted, your user name shortened to `~`, file mode 600.",
        .privacySection: "Privacy",
        .privacyText: "No network access. Nothing leaves this Mac; an export only writes to the file you pick.",
        .privacyBadge: "A redacted audit record will be written",
        .settingsVersion: "v%@ · %d events · %d sessions",

        .usageSummary: "Last %d days · %@ tokens · %d days",
        .dailyTokens: "Daily tokens",
        .noTokenData: "No token counts yet. They appear here once an agent writes a counter during a session.",
        .token: "Token",
        .byAgent: "By agent",
        .processedTokens: "tokens processed",
        .counterCount: "%d counters",
        .noCounterData: "No session wrote a token counter in this range. They add up here as the agents report them.",
        .usageNote: "Numbers are summed from the counters the agents write into their own transcripts. No prices: the same token is worth different money depending on plan and model.",

        .statusScan: "%d events scanned · %d updated · %.2f s",
        .statusError: "Error: %@",
        .statusPrune: "Removed: %d events, %d sessions",
        .statusPruneFailed: "Cleanup failed: %@",
        .statusExport: "%@ · %d events, %d findings · %.2f s",
        .statusExportFailed: "Export failed: %@",

        .onboardingTitle: "What am I reading?",
        .onboardingPrivacy: "Nothing leaves this Mac: there is no network access, everything stays local. Your transcripts stay where they are — they are only ever read.",

        .axisDay: "Day",
        .quit: "Quit",
        .missingFolder: "missing"
    ]
}
