// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// Folders that are read? Retention? Where does an export go? All of it here,
/// with the privacy promise stated where the settings live.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var loginItem: LoginItem

    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.standard.rawValue
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage("trailwarden.retentionDays") private var retentionDays = 90
    @AppStorage("trailwarden.exportFormat") private var exportFormat = AuditFormat.markdown.rawValue
    @State private var roots: [TranscriptRoot] = AppModel.transcriptRoots()
    @AppStorage(LiveMonitor.enabledKey) private var liveEnabled = true
    @AppStorage(LiveMonitor.thresholdKey) private var liveThreshold = Severity.critical.rawValue

    private var format: AuditFormat {
        AuditFormat(rawValue: exportFormat) ?? .markdown
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(20)
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.environment["TRAILWARDEN_OPEN_MODE"] == "prices" {
                    try? await Task.sleep(for: .seconds(1))
                    proxy.scrollTo("prices", anchor: .top)
                }
            }
            #endif
        }
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Hairline()
            LiveSection(
                live: model.live,
                loginItem: loginItem,
                enabled: $liveEnabled,
                threshold: $liveThreshold)
            Hairline()
            appearanceSection
            Hairline()
            languageSection
            Hairline()
            rootsSection
            Hairline()
            retentionSection
            Hairline()
            exportSection
            Hairline()
            UpdateSection(updates: updates)
            Hairline()
            PricesSection(book: model.priceBook, updates: updates)
                .id("prices")
            Hairline()
            privacySection
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L(.windowSettings))
                .font(Tokens.Typography.font(.title, weight: .semibold))
            Text(Lf(
                .settingsVersion,
                [TrailwardenVersion.current, model.snapshot.totalEvents, model.snapshot.sessions.count]))
                .font(Tokens.Typography.font(.codeSmall))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.appearance))
            Picker(L(.appearance), selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .onChange(of: appearance) { _, value in
                AppearanceMode(rawValue: value)?.apply()
            }
            Text(L(.appearanceHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
            SectionLabel(text: L(.textSizeSection))
                .padding(.top, 4)
            Picker(L(.textSizeSection), selection: $textSize) {
                ForEach(TextSize.allCases) { size in
                    Text(size.label).tag(size.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.languageSection))
            Picker("", selection: $language) {
                Text(L(.languageSystem)).tag(AppLanguage.system.rawValue)
                ForEach(AppLanguage.translated) { option in
                    Text(option.endonym).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 260)
            Text(L(.languageHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var rootsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.scannedDirs))
            ForEach(roots) { root in
                HStack(alignment: .firstTextBaseline) {
                    Text(EventFormatting.agentLabel(root.agent))
                        .font(Tokens.Typography.font(.codeSmall))
                        .frame(width: 70, alignment: .leading)
                    Text(ProjectName.display(root.path))
                        .font(Tokens.Typography.font(.codeSmall))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(root.exists ? Lf(.filesCount, [root.files]) : L(.missingFolder))
                        .font(Tokens.Typography.font(.caption))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
            }
            Text(L(.dirsHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.retention))
            HStack(spacing: 8) {
                Stepper(value: $retentionDays, in: 30 ... 365, step: 30) {
                    Text(Lf(.retentionDays, [retentionDays]))
                        .font(Tokens.Typography.font(.body))
                }
                Button(L(.cleanupNow)) {
                    Task { await model.prune(retentionDays: retentionDays) }
                }
                .buttonStyle(.plain)
                .font(Tokens.Typography.font(.callout, weight: .medium))
                .foregroundStyle(Tokens.Palette.accentText)
            }
            Text(L(.retentionHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.exportSection))
            HStack(spacing: 10) {
                Picker("", selection: $exportFormat) {
                    ForEach(AuditFormat.allCases) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Button(L(.exportAction)) { exportNow() }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.font(.callout, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accentText)
                Spacer()
                Text(L(.exportRange))
                    .font(Tokens.Typography.font(.caption))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Text(L(.exportHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status = model.maintenanceStatus {
                Text(status)
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: L(.privacySection))
            Text(L(.privacyText))
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportNow() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportWriter.suggestedFilename(format: format)
        panel.canCreateDirectories = true
        panel.message = L(.privacyBadge)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.export(format: format, days: 30, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

/// The live guard switch and what it notifies about. Its own view so it can
/// observe the monitor (running, notification permission) directly.
private struct LiveSection: View {
    @ObservedObject var live: LiveMonitor
    @ObservedObject var loginItem: LoginItem
    @Binding var enabled: Bool
    @Binding var threshold: String

    /// Follows the system's answer rather than a stored flag, so a change made in
    /// System Settings is what the switch shows.
    private var opensAtLogin: Binding<Bool> {
        Binding(
            get: { loginItem.status == .enabled || loginItem.status == .requiresApproval },
            set: { loginItem.setEnabled($0) })
    }

    private static let becameActive = NotificationCenter.default
        .publisher(for: NSApplication.didBecomeActiveNotification)

    private var loginItemLine: String {
        switch loginItem.status {
        case .enabled: L(.loginItemOn)
        case .disabled: L(.loginItemOff)
        case .requiresApproval: L(.loginItemNeedsApproval)
        case let .failed(message): message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: L(.liveGuard))
                Spacer()
                Toggle("", isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .onChange(of: enabled) { _, _ in
                        live.sync()
                    }
            }
            HStack(spacing: 8) {
                Text(L(.liveNotifyFor))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
                Picker("", selection: $threshold) {
                    Text(L(.liveCriticalOnly)).tag(Severity.critical.rawValue)
                    Text(L(.liveWarnAndCritical)).tag(Severity.warn.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                .disabled(!enabled)
                .onChange(of: threshold) { _, _ in
                    live.restart()
                }
            }
            Text(L(.liveGuardHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: opensAtLogin) {
                    Text(L(.loginItemTitle))
                        .font(Tokens.Typography.font(.callout))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text(loginItemLine)
                    .font(Tokens.Typography.font(.caption))
                    .foregroundStyle(Tokens.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if loginItem.status == .requiresApproval {
                    Button(L(.loginItemOpenSettings)) {
                        loginItem.openLoginItemsSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .onAppear { loginItem.refresh() }
            .onReceive(Self.becameActive) { _ in
                loginItem.refresh()
            }
            if enabled, !live.notificationsAllowed {
                VStack(alignment: .leading, spacing: 6) {
                    // "Turned off" only when the answer was no; before anyone has
                    // been asked, say what the permission is for.
                    Text(live
                        .permission == .denied ? L(.liveNotificationsDenied) : L(.onboardingNotifications))
                        .font(Tokens.Typography.font(.caption, weight: .medium))
                        .foregroundStyle(Tokens.Palette.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        // Once the answer is "no" the system will not prompt again;
                        // only System Settings can change it.
                        if live.permission != .denied {
                            Button(L(.liveAllowNotifications)) {
                                live.requestNotifications()
                            }
                        }
                        Button(L(.liveOpenNotificationSettings)) {
                            // The modern pane; the old identifier is gone on 14+.
                            if let url =
                                URL(
                                    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                            {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Off, weekly or monthly — and when the feed was last read. The schedule is
/// the reader's choice; the default never goes online on its own.
private struct UpdateSection: View {
    @ObservedObject var updates: UpdateChecker
    @AppStorage(UpdateSchedule.storageKey) private var schedule = UpdateSchedule.never.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.updateSchedule))
            HStack(spacing: 10) {
                Picker("", selection: $schedule) {
                    Text(L(.updateScheduleNever)).tag(UpdateSchedule.never.rawValue)
                    Text(L(.updateScheduleWeekly)).tag(UpdateSchedule.weekly.rawValue)
                    Text(L(.updateScheduleMonthly)).tag(UpdateSchedule.monthly.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                .onChange(of: schedule) { _, _ in
                    updates.startSchedule()
                }
                Button(updates.state == .checking ? L(.checkingUpdates) : L(.checkUpdates)) {
                    Task { await updates.check() }
                }
                .disabled(updates.state == .checking)
            }
            Text(lastLine)
                .font(Tokens.Typography.font(.codeSmall))
                .foregroundStyle(Tokens.Palette.secondary)
            Text(L(.updateScheduleHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lastLine: String {
        var line = updates.lastCheck.map { Lf(.updateLastChecked, [EventFormatting.stamp($0)]) }
            ?? L(.updateNeverChecked)
        switch updates.state {
        case .upToDate: line += " · " + L(.upToDate)
        case let .available(feed): line += " · " + Lf(.updateAvailable, [feed.version])
        case .failed: line += " · " + L(.updateCheckFailed)
        case .idle, .checking: break
        }
        return line
    }
}
