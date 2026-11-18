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

    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Hairline()
                LiveSection(live: model.live, enabled: $liveEnabled, threshold: $liveThreshold)
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
                privacySection
            }
            .padding(20)
        }
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L(.windowSettings))
                .font(Tokens.Typography.serif(18, weight: .semibold))
            Text(Lf(
                .settingsVersion,
                [TrailwardenVersion.current, model.snapshot.totalEvents, model.snapshot.sessions.count]))
                .font(Tokens.Typography.mono(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.appearance))
            Picker("", selection: $appearance) {
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
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
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
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var rootsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.scannedDirs))
            ForEach(roots) { root in
                HStack(alignment: .firstTextBaseline) {
                    Text(EventFormatting.agentLabel(root.agent))
                        .font(Tokens.Typography.mono(9))
                        .frame(width: 70, alignment: .leading)
                    Text(ProjectName.display(root.path))
                        .font(Tokens.Typography.mono(9.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(root.exists ? Lf(.filesCount, [root.files]) : L(.missingFolder))
                        .font(Tokens.Typography.text(9))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
            }
            Text(L(.dirsHint))
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.retention))
            HStack(spacing: 8) {
                Stepper(value: $retentionDays, in: 30 ... 365, step: 30) {
                    Text(Lf(.retentionDays, [retentionDays]))
                        .font(Tokens.Typography.text(11))
                }
                Button(L(.cleanupNow)) {
                    Task { await model.prune(retentionDays: retentionDays) }
                }
                .buttonStyle(.plain)
                .font(Tokens.Typography.text(10, weight: .medium))
                .foregroundStyle(Tokens.Palette.accent)
            }
            Text(L(.retentionHint))
                .font(Tokens.Typography.text(9.5))
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
                    .font(Tokens.Typography.text(10.5, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
                Spacer()
                Text(L(.exportRange))
                    .font(Tokens.Typography.text(9.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Text(L(.exportHint))
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let status = model.maintenanceStatus {
                Text(status)
                    .font(Tokens.Typography.mono(9))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: L(.privacySection))
            Text(L(.privacyText))
                .font(Tokens.Typography.text(10))
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
    @Binding var enabled: Bool
    @Binding var threshold: String

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
                    .font(Tokens.Typography.text(10.5))
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
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled, !live.notificationsAllowed {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(.liveNotificationsDenied))
                        .font(Tokens.Typography.text(9.5, weight: .medium))
                        .foregroundStyle(Tokens.Palette.accent)
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
                .font(Tokens.Typography.mono(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
            Text(L(.updateScheduleHint))
                .font(Tokens.Typography.text(9.5))
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
