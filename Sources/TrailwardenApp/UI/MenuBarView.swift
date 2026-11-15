// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// The menu bar panel: a five-second answer to three questions — is anything
/// wrong, what did the agent just do, and how do I get to the detail.
///
/// It used to lead with "hermes · ~ · 6 events" rows, which are all identical to
/// a reader, and with a database count nobody asked for. Rows are actions now:
/// the tool, the thing it touched, the time.
struct MenuBarView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            if model.onboardingDone {
                status
                Hairline()
                activity
            } else {
                OnboardingView(model: model)
            }
            Hairline()
            if let line = updateLine {
                HStack(spacing: 6) {
                    Image(systemName: line.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(line.tint)
                    Text(line.text)
                        .font(Tokens.Typography.text(10.5, weight: line.weight))
                        .foregroundStyle(line.tint)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let link = line.link {
                        Button(L(.releaseNotes)) {
                            NSWorkspace.shared.open(link)
                        }
                        .buttonStyle(.plain)
                        .font(Tokens.Typography.text(10.5, weight: .medium))
                        .foregroundStyle(Tokens.Palette.accent)
                    }
                }
                .padding(.horizontal, Tokens.Metrics.gutter)
                .padding(.vertical, 7)
                Hairline()
            }
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

    // MARK: - Status

    /// One sentence about today's risk, not a count without a subject: the
    /// number only means something next to the command that caused it.
    private var status: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: L(.today))
            if let critical = model.snapshot.latestCritical {
                Button {
                    model.findingsRequested += 1
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(model.snapshot.criticalToday)")
                            .font(Tokens.Typography.serif(20, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.accent)
                        Text(L(.severityCritical))
                            .font(Tokens.Typography.text(10))
                            .foregroundStyle(Tokens.Palette.secondary)
                        Text(time(critical.time))
                            .font(Tokens.Typography.mono(9))
                            .foregroundStyle(Tokens.Palette.tertiary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L(.whatHappened))
                if let rule = critical.ruleMessage {
                    Text(rule)
                        .font(Tokens.Typography.text(10))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1)
                }
                if !critical.detail.isEmpty {
                    Text(critical.detail)
                        .font(Tokens.Typography.mono(9.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if model.snapshot.totalEvents == 0 {
                Text(model.isScanning ? L(.scanning) : L(.noDataYet))
                    .font(Tokens.Typography.text(10.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                Text(L(.nothingRiskyToday))
                    .font(Tokens.Typography.text(11))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(Tokens.Typography.text(10))
                    .foregroundStyle(Tokens.Palette.accent)
                    .lineLimit(2)
            }
            if model.snapshot.messagesToday > 0 {
                Text(Lf(.messagesToday, [model.snapshot.messagesToday]))
                    .font(Tokens.Typography.text(9))
                    .foregroundStyle(Tokens.Palette.tertiary)
            }
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 11)
    }

    // MARK: - Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: L(.whatHappened))
            if model.snapshot.recentActions.isEmpty {
                Text(L(.noSessionsFound))
                    .font(Tokens.Typography.text(10.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                ForEach(model.snapshot.recentActions) { item in
                    actionRow(item)
                }
            }
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 11)
    }

    /// A row opens the timeline on the session it belongs to.
    private func actionRow(_ item: ActivityItem) -> some View {
        Button {
            model.sessionToOpen = item.sessionID
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(time(item.time))
                    .font(Tokens.Typography.mono(8.5))
                    .foregroundStyle(Tokens.Palette.tertiary)
                    .frame(width: 74, alignment: .leading)
                Text(item.label)
                    .font(Tokens.Typography.mono(9, weight: .medium))
                    .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                Text(item.detail)
                    .font(Tokens.Typography.text(9.5))
                    .foregroundStyle(item.isMessage ? Tokens.Palette.tertiary : Tokens.Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 2)
                if let severity = item.severity {
                    Circle()
                        .fill(Tokens.Palette.severity(severity))
                        .frame(width: 5, height: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.ruleMessage ?? item.detail)
    }

    // MARK: - Updates

    /// The result of the one network call the reader can start. It lives in the
    /// panel rather than in a modal: a version number does not deserve an alert.
    private struct UpdateLine {
        let icon: String
        let text: String
        let tint: Color
        let weight: Font.Weight
        let link: URL?
    }

    private var updateLine: UpdateLine? {
        switch updates.state {
        case .idle:
            return nil
        case .checking:
            return UpdateLine(
                icon: "arrow.triangle.2.circlepath", text: L(.checkingUpdates),
                tint: Tokens.Palette.secondary, weight: .regular, link: nil)
        case .upToDate:
            return UpdateLine(
                icon: "checkmark.seal", text: L(.upToDate),
                tint: Tokens.Palette.secondary, weight: .regular, link: nil)
        case let .available(feed):
            let text = Lf(.updateAvailable, [feed.version])
            return UpdateLine(
                icon: "arrow.down.circle", text: feed.notes.map { "\(text) — \($0)" } ?? text,
                tint: Tokens.Palette.accent, weight: .medium, link: feed.url)
        case .failed:
            return UpdateLine(
                icon: "exclamationmark.triangle", text: L(.updateCheckFailed),
                tint: Tokens.Palette.secondary, weight: .regular, link: nil)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(L(.openDashboard), tint: Tokens.Palette.accent, weight: .medium) {
                openWindow(id: "main")
            }
            footerButton(L(.windowUsage)) {
                openWindow(id: "usage")
            }
            footerButton(L(.windowSettings)) {
                openWindow(id: "settings")
            }
            footerButton(L(.windowRules), weight: .medium) {
                openWindow(id: "rules")
            }

            Button {
                Task { await updates.check() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .buttonStyle(.plain)
            .disabled(updates.state == .checking)
            .help(L(.checkUpdates))

            Spacer(minLength: 4)

            if !model.liveSessions.isEmpty {
                Text(Lf(.liveCount, [model.liveSessions.count]))
                    .font(Tokens.Typography.mono(9, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            }

            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            } else if model.onboardingDone {
                footerButton(L(.scan), weight: .medium) {
                    Task { await model.scan() }
                }
            }

            footerButton(L(.quit), tint: Tokens.Palette.secondary) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 10)
    }

    private func footerButton(
        _ title: String,
        tint: Color = Tokens.Palette.ink,
        weight: Font.Weight = .regular,
        action: @escaping () -> Void)
        -> some View
    {
        Button {
            action()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Text(title)
                .font(Tokens.Typography.text(11, weight: weight))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private func time(_ date: Date) -> String {
        EventFormatting.stamp(date)
    }
}
