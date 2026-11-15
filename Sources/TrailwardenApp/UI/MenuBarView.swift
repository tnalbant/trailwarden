// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

struct MenuBarView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            if model.onboardingDone {
                summary
                Hairline()
                recentSessions
            } else {
                OnboardingView(model: model)
            }
            Hairline()
            footer
        }
        .frame(width: Tokens.Metrics.panelWidth)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Trailwarden")
                .font(Tokens.Typography.serif(14, weight: .semibold))
            Spacer()
            Text("v\(TrailwardenVersion.current)")
                .font(Tokens.Typography.mono(9))
                .foregroundStyle(Tokens.Palette.secondary)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 11)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.today))
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                metric(model.snapshot.criticalToday, label: L(.severityCritical), tinted: true)
                metric(model.snapshot.warnToday, label: L(.severityWarning), tinted: false)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(model.snapshot.totalEvents)")
                        .font(Tokens.Typography.mono(11))
                    Text(L(.events))
                        .font(Tokens.Typography.text(9))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
            }
            if model.snapshot.totalEvents == 0 {
                Text(model.isScanning ? L(.scanning) : L(.noDataYet))
                    .font(Tokens.Typography.text(10.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else if let error = model.errorMessage {
                Text(error)
                    .font(Tokens.Typography.text(10))
                    .foregroundStyle(Tokens.Palette.accent)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 12)
    }

    private func metric(_ value: Int, label: String, tinted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)")
                .font(Tokens.Typography.serif(22, weight: .semibold))
                .foregroundStyle(tinted && value > 0 ? Tokens.Palette.accent : Tokens.Palette.ink)
            Text(label)
                .font(Tokens.Typography.text(10))
                .foregroundStyle(Tokens.Palette.secondary)
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Son oturumlar")
            if model.snapshot.recentSessions.isEmpty {
                Text(L(.noSessionsFound))
                    .font(Tokens.Typography.text(10.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                ForEach(model.snapshot.recentSessions) { session in
                    sessionRow(session)
                }
            }
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 12)
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(EventFormatting.agentLabel(session.agent))
                .font(Tokens.Typography.mono(8.5))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Tokens.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text(projectName(session.cwd))
                    .font(Tokens.Typography.mono(10.5))
                    .lineLimit(1)
                Text(Lf(.sessionMeta, [time(session.startedAt), session.eventCount]))
                    .font(Tokens.Typography.text(9))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Spacer(minLength: 4)
            if session.criticalCount > 0 {
                Text(Lf(.sessionCritical, [session.criticalCount]))
                    .font(Tokens.Typography.text(9, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text(L(.openDashboard))
                    .font(Tokens.Typography.text(11, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "usage")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text(L(.windowUsage))
                    .font(Tokens.Typography.text(11))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text(L(.windowSettings))
                    .font(Tokens.Typography.text(11))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "rules")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text(L(.windowRules))
                    .font(Tokens.Typography.text(11, weight: .medium))
                    .foregroundStyle(Tokens.Palette.ink)
            }
            .buttonStyle(.plain)

            Spacer()

            if !model.liveSessions.isEmpty {
                Text(Lf(.liveCount, [model.liveSessions.count]))
                    .font(Tokens.Typography.mono(9, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            }

            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            } else if model.onboardingDone {
                // During onboarding the big button already starts the scan.
                Button {
                    Task { await model.scan() }
                } label: {
                    Text(L(.scan))
                        .font(Tokens.Typography.text(11, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Text(L(.quit))
                    .font(Tokens.Typography.text(11))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 10)
    }

    private func projectName(_ cwd: String?) -> String {
        guard let cwd else { return "—" }
        let shortened = Redactor().shortenHome(cwd)
        return shortened.split(separator: "/").last.map(String.init) ?? shortened
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
