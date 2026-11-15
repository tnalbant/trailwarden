// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// Folders that are read? Retention? Where does an export go? All of it here,
/// with the privacy promise stated where the settings live.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage("trailwarden.retentionDays") private var retentionDays = 90
    @AppStorage("trailwarden.exportFormat") private var exportFormat = AuditFormat.markdown.rawValue
    @State private var roots: [TranscriptRoot] = AppModel.transcriptRoots()

    private var format: AuditFormat {
        AuditFormat(rawValue: exportFormat) ?? .markdown
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
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
