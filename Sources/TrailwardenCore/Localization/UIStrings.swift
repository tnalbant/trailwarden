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
    /// The noun that turns a bare id in the window row into a readable selection
    case labelSession
    /// Placeholder in the search field (was hardcoded Turkish)
    case searchPlaceholder
    /// The one network call, made only when the reader asks for it
    case checkUpdates, checkingUpdates, upToDate, updateAvailable, updateCheckFailed, releaseNotes
    /// Windows and panels
    case windowRules, windowUsage, windowSettings, openDashboard, recentSessions
    /// Activity feed — what the agent did, not how many rows the database holds
    case whatHappened, nothingRiskyToday, todayFeed, timelineTab, messagesToday
    /// Recovery from a filter combination that matches nothing
    case clearFilters
    /// Short range labels: a popup button cannot hold "Last 30 days" next to four
    /// other filters and a search field.
    case rangeDay, rangeWeek, rangeMonth, rangeAll
    // Counts
    case events, event, findings, sessions, eventCount, sessionMeta, sessionCritical
    case projectMeta, liveCount, liveTooltip, eventsRatio
    /// Session sidebar: the fallback title and the day groups
    /// A transcript the agent deleted: the sidebar badge and the reason resume is off
    case sourceDeleted, resumeSourceDeleted
    case untitledSession, groupToday, groupYesterday, groupThisWeek, groupOlder
    // Empty states
    case noDataYet, noSessionsFound, noSessionSelected, noEventsInRange, noEventsHint
    case pickEvent, pickEventHint, loadMore
    // Scanning
    case scanning, scanningProgress, rescan, scan, startScan, filesCount
    // Severity
    case severityCritical, severityWarning, severityInfo
    // Event detail
    /// Plain verbs for what an event did
    case verbRan, verbEdited, verbWrote, verbRead, verbSearched, verbSaid, verbThought, verbOther
    case labelCommand, labelText, labelDiff, labelPaths, labelRaw
    case resumeSession, copy, copied, whyFlagged
    // Allow sheet and allowance list
    case allowEllipsis, allowHint, allowSheetTitle, allowScopeLabel, allowPatternLabel, allowPatternHint
    case scopeCommand, scopeProject, scopePattern, scopeEverywhere
    case kindCommand, kindProject, kindPattern, kindEverywhere, allowEverywhereValue
    case allowDurationLabel, durationOneDay, durationThirtyDays, durationForever, allowForeverRemaining
    case scopeEditLabel, scopeEditPattern, scopeEditEverywhere, scopeEditApply
    case allowConfirm, cancel, allowedBadge, allowedAccessibility
    // Rules
    case rulesIntro, disableRule, enableRule, ruleHits, ruleMatchesAll, ruleTool
    case mutedRules, noMutes, removeMute, daysLeft, muteExpired, reapplying, reapply
    // Filters
    case allAgents, onlyFindings, rawStream, showCountersHint
    // Settings
    case appearance, appearanceAutomatic, appearanceLight, appearanceDark, appearanceHint
    case textSizeSection, textSizeStandard, textSizeLarge, textSizeLarger
    case technicalDetailsToggle, technicalDetailsHint, ruleExamplesMatch, ruleExamplesIgnore
    case outsideProject, genericError
    /// Spoken names for controls that show no visible label
    case rangePickerLabel, agentPickerLabel, severityPickerLabel, languagePickerLabel
    case exportFormatLabel, updateSchedulePickerLabel, liveThresholdLabel, selected
    case languageSection, languageSystem, languageHint
    case scannedDirs, dirsHint, retention, retentionDays, cleanupNow, retentionHint
    case exportSection, exportAction, exportRange, exportHint
    case privacySection, privacyText, privacyBadge, settingsVersion
    // Usage
    case usageSummary, dailyTokens, noTokenData, token, byAgent, processedTokens
    case counterCount, noCounterData, usageNote
    case byModel, apiEquivalent, estimatedCost, priceUnknown, priceFree, unpricedNote, priceNote,
         priceFileError, noteTitle
    /// Settings › Prices: the reader's own prices and the manual list update
    case pricesSection, priceListBuiltIn, priceListDownloaded, checkPrices, checkingPrices
    case pricesUpdated, pricesCurrent, pricesCheckFailed, pricesStale, pricesHint
    case priceModel, priceInput, priceOutput, priceCacheRead, priceCacheWrite, priceFreeToggle
    case priceSave, priceReset, priceSourceBuiltIn, priceSourcePublished, priceSourceUser
    case addModel, addModelPlaceholder, noPriceModels, priceSaveFailed
    case pricesWindow, editPrices, pricesSummary, searchModels, onlyUnpriced, noPriceMatches
    // Status line
    case statusScan, statusError, statusPrune, statusPruneFailed
    case statusExport, statusExportFailed
    // Onboarding
    case onboardingTitle, onboardingPrivacy, onboardingNotifications
    // Small words
    case axisDay, quit, missingFolder
    // Live guard
    case sections
    case liveGuard, liveGuardHint, liveOn, liveOff, liveNotifyFor, liveCriticalOnly, liveWarnAndCritical
    case liveNotificationsDenied, liveMoreFindings, liveAllowNotifications, liveOpenNotificationSettings
    case liveNotificationsAllowed
    // Launch at login
    case loginItemTitle, loginItemOn, loginItemOff, loginItemNeedsApproval, loginItemOpenSettings
    case loginItemFailed, guardOffBanner, guardOffAction
    // Report card
    case windowReport, reportTitle, reportWork, reportCommands, reportEdits, reportReads, reportFilesChanged
    case reportWorthALook, reportNoFindings, reportByAgent, reportHotFiles, reportRules, reportCopySummary
    case reportSummaryHint, reportEmpty, reportShareTitle, reportShareFiles, reportShareFindings
    case reportShareFooter, reportOpen
    // File history in the detail pane
    case whoTouched, whoNone
    // Last interface strings that were hardcoded
    case eventsNone, range90Days, touchChanged, touchRead, touchNamed
    case tokenInput, tokenCacheRead, tokenCacheWrite, tokenOutput, tokenReasoning, activeDays
    // Scheduled update check
    case updateSchedule, updateScheduleNever, updateScheduleWeekly, updateScheduleMonthly
    case updateScheduleHint, updateLastChecked, updateNeverChecked, updateNotificationTitle
    // Inbox
    case inboxTab, inboxActivityHeading, inboxEmpty, inboxWaiting, inboxBacklogTitle
    case inboxMarkAllReviewed, inboxShowThem, inboxReviewed, inboxExpectedHere, inboxFalseAlarm
    case inboxOpen, inboxLine
}

public enum UITranslations {
    public static let english: [UIString: String] = [
        .today: "Today",
        .last7Days: "7 days",
        .last30Days: "30 days",
        .allTime: "All time",
        .allSessions: "All sessions",
        .labelSession: "Session",
        .searchPlaceholder: "Search",
        .checkUpdates: "Check for updates",
        .checkingUpdates: "Checking…",
        .upToDate: "You are up to date",
        .updateAvailable: "%@ is available",
        .updateCheckFailed: "Could not check for updates",
        .releaseNotes: "Release notes",
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
        .inboxTab: "Inbox",
        .inboxActivityHeading: "Today’s activity",
        .inboxEmpty: "Nothing is waiting for review.",
        .inboxWaiting: "%d critical findings waiting for review →",
        .inboxBacklogTitle: "Trailwarden found %d findings from before today.",
        .inboxMarkAllReviewed: "Mark them all reviewed",
        .inboxShowThem: "Show them in the inbox",
        .inboxReviewed: "Reviewed",
        .inboxExpectedHere: "Expected in this project",
        .inboxFalseAlarm: "False alarm",
        .inboxOpen: "Open",
        .inboxLine: "line %d",
        .timelineTab: "Timeline",
        .messagesToday: "%d messages",
        .clearFilters: "Clear filters",
        .rangeDay: "Day",
        .rangeWeek: "Week",
        .rangeMonth: "Month",
        .rangeAll: "All",

        .events: "events",
        .event: "event",
        .findings: "findings",
        .sessions: "sessions",
        .eventCount: "%d events",
        .sessionMeta: "%@ · %d events",
        .sessionCritical: "%d critical",
        .projectMeta: "%d sessions · %d events",
        .sourceDeleted: "Source deleted — kept in Trailwarden",
        .resumeSourceDeleted: "The agent deleted this session's file, so it cannot be resumed. Trailwarden still has its history.",
        .untitledSession: "Untitled session",
        .groupToday: "Today",
        .groupYesterday: "Yesterday",
        .groupThisWeek: "This week",
        .groupOlder: "Older",
        .liveCount: "%d live",
        .liveTooltip: "This session wrote in the last two minutes — the agent may still be running",
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
        .scanningProgress: "Scanning… %d%%",
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

        .rulesIntro: "Turning a rule off, or changing its severity, re-evaluates the index right away — past events are re-flagged under the new setting.",
        .disableRule: "Turn rule off",
        .enableRule: "Turn rule on",
        .ruleHits: "%d events",
        .ruleMatchesAll: "every event",
        .ruleTool: "tool: %@",
        .mutedRules: "Allowed",
        .noMutes: "Nothing allowed yet. Open a finding and choose “Allow…” to add one.",
        .removeMute: "Remove",
        .daysLeft: "%d days",
        .muteExpired: "expired",
        .scopeEditLabel: "Change scope",
        .scopeEditPattern: "Pattern…",
        .scopeEditEverywhere: "Everywhere",
        .scopeEditApply: "Apply",
        .allowEllipsis: "Allow…",
        .allowHint: "Tell Trailwarden this is expected, for a scope and a time you choose",
        .allowSheetTitle: "Allow this finding",
        .allowScopeLabel: "Where should it be allowed?",
        .allowPatternLabel: "Pattern",
        .allowPatternHint: "* stays inside one folder, ** crosses folders.",
        .scopeCommand: "This exact command",
        .scopeProject: "Everything this rule flags in %@",
        .scopePattern: "Anything matching a pattern",
        .scopeEverywhere: "Everywhere, for every project",
        .kindCommand: "Command",
        .kindProject: "Project",
        .kindPattern: "Pattern",
        .kindEverywhere: "Everywhere",
        .allowEverywhereValue: "every match of this rule",
        .allowDurationLabel: "For how long?",
        .durationOneDay: "1 day",
        .durationThirtyDays: "30 days",
        .durationForever: "Forever",
        .allowForeverRemaining: "no end",
        .allowConfirm: "Allow",
        .cancel: "Cancel",
        .allowedBadge: "Allowed",
        .allowedAccessibility: "Allowed: %@",
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
        .textSizeSection: "Text size",
        .textSizeStandard: "Standard",
        .textSizeLarge: "Large",
        .textSizeLarger: "Larger",
        .technicalDetailsToggle: "Show technical details",
        .technicalDetailsHint: "Adds tool names, rule ids, session ids, raw records and full error text.",
        .ruleExamplesMatch: "Flags",
        .ruleExamplesIgnore: "Leaves alone",
        .outsideProject: "outside the project",
        .genericError: "Something went wrong. Turn on technical details to see the error.",
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
        .privacyText: "Nothing about your agents leaves this Mac. The app goes online only to check for updates (when you click, or on the schedule above) and to read the public price list when you click \"Update prices\"; neither sends anything about you. An export only writes to the file you pick.",
        .privacyBadge: "A redacted audit record will be written",
        .settingsVersion: "v%@ · %d events · %d sessions",

        .usageSummary: "Last %d days · %@ tokens · %@",
        .dailyTokens: "Daily tokens",
        .noTokenData: "No token counts yet. They appear here once an agent writes a counter during a session.",
        .token: "Token",
        .byAgent: "By agent",
        .processedTokens: "tokens processed",
        .counterCount: "%d counters",
        .noCounterData: "No session wrote a token counter in this range. They add up here as the agents report them.",
        .usageNote: "Numbers are summed from the counters the agents write into their own transcripts. Cache reads are counted with the rest; they are most of the tokens and the cheapest ones.",
        .byModel: "By model",
        .apiEquivalent: "API equivalent",
        .estimatedCost: "≈ %@ at API prices",
        .priceUnknown: "no price",
        .priceFree: "free",
        .unpricedNote: "%@ tokens from %d models have no price yet and are left out of the estimate.",
        .priceNote: "An estimate: what these tokens would have cost on each provider's pay-as-you-go API, at the prices of %@. A subscription costs what you pay for it. Default tiers only (short context, 5-minute cache writes, peak hours). To add a model, enter your own price or mark one free, open Settings › Prices.",
        .priceFileError: "Your price file could not be read, so your own prices are not applied: %@",
        .noteTitle: "Note",
        .pricesSection: "Prices · USD per million tokens",
        .priceListBuiltIn: "Price list of %@, built into the app",
        .priceListDownloaded: "Price list of %@, downloaded",
        .checkPrices: "Update prices",
        .checkingPrices: "Checking…",
        .pricesUpdated: "New price list of %@ loaded",
        .pricesCurrent: "Already up to date",
        .pricesCheckFailed: "The price list could not be read",
        .pricesStale: "These prices are more than 60 days old and may have changed. Use \"Update prices\" in Settings › Prices.",
        .pricesHint: "The price window lists the models your agents used in the last 90 days, the ones without a price first. A price you enter always wins: updating the list never changes it. \"Update prices\" reads one public file from the project's GitHub page and sends nothing.",
        .priceModel: "Model",
        .priceInput: "Input",
        .priceOutput: "Output",
        .priceCacheRead: "Cache read",
        .priceCacheWrite: "Cache write",
        .priceFreeToggle: "Free",
        .priceSave: "Save",
        .priceReset: "Use list price",
        .priceSourceBuiltIn: "list price",
        .priceSourcePublished: "downloaded price",
        .priceSourceUser: "your price",
        .addModel: "Add",
        .addModelPlaceholder: "Another model id, e.g. gpt-6-sol",
        .noPriceModels: "No models yet. They appear once an agent reports tokens.",
        .priceSaveFailed: "Could not save the price.",
        .pricesWindow: "Prices",
        .editPrices: "Edit prices…",
        .pricesSummary: "%d models · %d without a price · %d of your own",
        .searchModels: "Search models or agents",
        .onlyUnpriced: "Only models without a price",
        .noPriceMatches: "No model matches “%@”.",

        .statusScan: "%d events scanned · %d updated · %.2f s",
        .statusError: "Error: %@",
        .statusPrune: "Removed: %d events, %d sessions",
        .statusPruneFailed: "Cleanup failed: %@",
        .statusExport: "%@ · %d events, %d findings · %.2f s",
        .statusExportFailed: "Export failed: %@",

        .onboardingNotifications: "Live alerts need notification permission.",
        .onboardingTitle: "What am I reading?",
        .onboardingPrivacy: "Nothing about your agents leaves this Mac. Your transcripts stay where they are and are only ever read; the one network request is the optional update check.",

        .axisDay: "Day",
        .quit: "Quit",
        .missingFolder: "missing",

        .sections: "Sections",
        .liveGuard: "Live guard",
        .liveGuardHint: "Re-reads a transcript the moment an agent writes to it and notifies you about risky commands. Nothing leaves the Mac.",
        .liveOn: "Live",
        .liveOff: "Live guard off",
        .liveNotifyFor: "Notify for",
        .liveCriticalOnly: "Critical only",
        .liveWarnAndCritical: "Warnings too",
        .liveNotificationsDenied: "Notifications are turned off for Trailwarden in System Settings.",
        .liveAllowNotifications: "Allow notifications",
        .liveNotificationsAllowed: "Notifications are on",
        .loginItemTitle: "Open Trailwarden when you log in",
        .loginItemOn: "Trailwarden opens when you log in.",
        .loginItemOff: "Trailwarden does not open when you log in.",
        .loginItemNeedsApproval: "Allow Trailwarden in System Settings to open at login.",
        .loginItemOpenSettings: "Open Login Items",
        .loginItemFailed: "Could not change the login item.",
        .guardOffBanner: "Live guard is off",
        .guardOffAction: "Turn on",
        .liveOpenNotificationSettings: "Open Notification Settings",
        .liveMoreFindings: "%d more findings — open Trailwarden to see them",
        .windowReport: "Report",
        .reportTitle: "Your agents, last %d days",
        .reportWork: "%d tool calls in %d sessions across %d projects",
        .reportCommands: "commands",
        .reportEdits: "edits",
        .reportReads: "reads",
        .reportFilesChanged: "files changed",
        .reportWorthALook: "Worth a look",
        .reportNoFindings: "Nothing risky in this window.",
        .reportByAgent: "Who did the work",
        .reportHotFiles: "Most-changed files",
        .reportRules: "Rules that fired",
        .reportCopySummary: "Copy summary",
        .reportSummaryHint: "The summary holds counts and rule names only — no commands, paths or project names.",
        .reportEmpty: "No agent activity in this window yet. Run a scan, or wait for the live guard.",
        .reportShareTitle: "My coding agents, last %d days",
        .reportShareFiles: "%d files changed",
        .reportShareFindings: "%d critical, %d warnings",
        .reportShareFooter: "Audited locally with Trailwarden — github.com/tnalbant/trailwarden",
        .reportOpen: "Open in timeline",
        .whoTouched: "Other sessions on this file",
        .whoNone: "No other session touched it.",
        .eventsNone: "0 events",
        .range90Days: "90 days",
        .touchChanged: "changed",
        .touchRead: "read",
        .touchNamed: "in a command",
        .tokenInput: "input",
        .tokenCacheRead: "cache read",
        .tokenCacheWrite: "cache write",
        .tokenOutput: "output",
        .tokenReasoning: "reasoning",
        .activeDays: "%d active days",

        .updateSchedule: "Automatic update check",
        .updateScheduleNever: "Off",
        .updateScheduleWeekly: "Weekly",
        .updateScheduleMonthly: "Monthly",
        .updateScheduleHint: "Off by default. When on, Trailwarden reads one small file from the latest GitHub release on this schedule. Nothing is sent: no identifiers, nothing about your agents.",
        .updateLastChecked: "Last checked %@",
        .updateNeverChecked: "Not checked yet",
        .updateNotificationTitle: "Trailwarden %@ is available",

        .verbRan: "Ran",
        .verbEdited: "Edited",
        .verbWrote: "Wrote",
        .verbRead: "Read",
        .verbSearched: "Searched",
        .verbSaid: "Said",
        .verbThought: "Thought",
        .verbOther: "Other",

        .rangePickerLabel: "Time range",
        .agentPickerLabel: "Agent",
        .severityPickerLabel: "Severity",
        .languagePickerLabel: "Language",
        .exportFormatLabel: "Export format",
        .updateSchedulePickerLabel: "Update check frequency",
        .liveThresholdLabel: "Notify for severity",
        .selected: "Selected"
    ]
}
