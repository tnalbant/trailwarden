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
    @ObservedObject var live: LiveMonitor
    @ObservedObject var router: DashboardRouter
    @Environment(\.openWindow) private var openWindow
    /// The places menu unfolds inside the panel: a `Menu` renders as an
    /// unsupported control inside a menu bar window.
    @State private var showsDestinations = false

    init(model: AppModel, updates: UpdateChecker, router: DashboardRouter) {
        self.model = model
        self.updates = updates
        self.router = router
        live = model.live
    }

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
            if model.onboardingDone {
                // Is anyone watching right now? Click to open the switch.
                Button {
                    openMain(.settings)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(live.isRunning ? Tokens.Palette.accent : Tokens.Palette.tertiary)
                            .frame(width: 6, height: 6)
                        Text(live.isRunning ? L(.liveOn) : L(.liveOff))
                            .font(Tokens.Typography.text(9.5, weight: .medium))
                            .foregroundStyle(live.isRunning ? Tokens.Palette.ink : Tokens.Palette.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(L(.liveGuardHint))
            }
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
                if let rule = critical.ruleLine(LocalizationStore.current) {
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
                Text(model.isScanning ? model.scanLabel : L(.noDataYet))
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
        .help(item.ruleLine(LocalizationStore.current) ?? item.detail)
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
        HStack(spacing: 10) {
            footerButton(L(.openDashboard), tint: Tokens.Palette.accent, weight: .medium) {
                openMain(nil)
            }

            if model.isScanning {
                if let progress = model.scanProgress, progress.filesTotal > 0 {
                    ProgressView(value: progress.fraction)
                        .frame(width: 60)
                        .help(model.scanLabel)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if model.onboardingDone {
                footerButton(L(.scan), weight: .medium) {
                    Task { await model.scan() }
                }
            }

            Spacer(minLength: 4)

            if !model.liveSessions.isEmpty {
                Text(Lf(.liveCount, [model.liveSessions.count]))
                    .font(Tokens.Typography.mono(9, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            }

            overflowButton
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 10)
    }

    /// The places rather than the actions: the panel keeps two buttons and one
    /// toggle, instead of a row of nine controls that each squeezed the next.
    private var overflowButton: some View {
        Button {
            showsDestinations.toggle()
        } label: {
            Image(systemName: showsDestinations ? "xmark" : "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tokens.Palette.secondary)
                .frame(width: 22, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Tokens.Palette.hairline)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(.sections))
    }

    /// Drawn inside the panel rather than as a pop-up menu: a `Menu` has no
    /// supported style in a menu bar window and came out as a "no entry" glyph.
    private var destinations: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationRow(L(.windowReport), tab: .report)
            destinationRow(L(.windowUsage), tab: .usage)
            destinationRow(L(.windowRules), tab: .rules)
            destinationRow(L(.windowSettings), tab: .settings)
            Divider()
                .padding(.vertical, 4)
            Button {
                showsDestinations = false
                Task { await updates.check() }
            } label: {
                destinationLabel(L(.checkUpdates))
            }
            .buttonStyle(.plain)
            .disabled(updates.state == .checking)
            Button {
                NSApp.terminate(nil)
            } label: {
                destinationLabel(L(.quit))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 6)
    }

    private func destinationRow(_ title: String, tab: DashboardTab) -> some View {
        Button {
            showsDestinations = false
            openMain(tab)
        } label: {
            destinationLabel(title)
        }
        .buttonStyle(.plain)
    }

    private func destinationLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Tokens.Typography.text(11))
                .foregroundStyle(Tokens.Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Every "open a place" goes through here: the window is one, the tab is the
    /// page, and the panel never has to know which window ids exist.
    private func openMain(_ tab: DashboardTab?) {
        if let tab {
            router.show(tab)
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
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
