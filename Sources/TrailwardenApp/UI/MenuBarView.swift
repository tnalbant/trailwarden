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
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.standard.rawValue
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var live: LiveMonitor
    @ObservedObject var router: DashboardRouter
    @ObservedObject var loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow
    /// The places menu unfolds inside the panel: a `Menu` renders as an
    /// unsupported control inside a menu bar window.
    @State private var showsDestinations = false

    init(model: AppModel, updates: UpdateChecker, router: DashboardRouter, loginItem: LoginItem) {
        self.model = model
        self.updates = updates
        self.router = router
        self.loginItem = loginItem
        live = model.live
        #if DEBUG
            // Screenshots need the unfolded list without a hand on the mouse.
            if ProcessInfo.processInfo.environment["TRAILWARDEN_PANEL_MORE"] == "1" {
                _showsDestinations = State(initialValue: true)
            }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.onboardingDone, !live.isRunning {
                guardOffStrip
            }
            if model.onboardingDone, case let .failed(message) = loginItem.status {
                loginFailedStrip(message)
            }
            updateBar
            Hairline()
            if model.onboardingDone {
                status
                Hairline()
                activity
            } else {
                OnboardingView(model: model, loginItem: loginItem)
            }
            Hairline()
            if showsDestinations {
                destinations
                Hairline()
            }
            footer
        }
        .id(textSize)
        .frame(width: Tokens.Metrics.panelWidth)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Trailwarden")
                .font(Tokens.Typography.font(.subtitle, weight: .semibold))
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
                            .font(Tokens.Typography.font(.caption, weight: .medium))
                            .foregroundStyle(live.isRunning ? Tokens.Palette.ink : Tokens.Palette.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(L(.liveGuardHint))
            }
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.top, 11)
        .padding(.bottom, 5)
    }

    /// The guard is the point of the app; when it is off, say so where the
    /// reader looks, with the way back.
    private var guardOffStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9))
                .foregroundStyle(Tokens.Palette.accent)
            Text(L(.guardOffBanner))
                .font(Tokens.Typography.font(.caption, weight: .medium))
            Spacer(minLength: 2)
            Button(L(.guardOffAction)) {
                openMain(.settings)
            }
            .buttonStyle(.plain)
            .font(Tokens.Typography.font(.caption, weight: .medium))
            .foregroundStyle(Tokens.Palette.accentText)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.bottom, 4)
    }

    /// A login item that could not be changed says so here, where the reader
    /// will see it, instead of only inside Settings.
    private func loginFailedStrip(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9))
                .foregroundStyle(Tokens.Palette.accent)
            Text(message)
                .font(Tokens.Typography.font(.caption, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Button(L(.windowSettings)) {
                openMain(.settings)
            }
            .buttonStyle(.plain)
            .font(Tokens.Typography.font(.caption, weight: .medium))
            .foregroundStyle(Tokens.Palette.accentText)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.bottom, 4)
    }

    /// The version and the one network call the reader can start, on the row
    /// under the title. A version number that hides in Settings is a version
    /// number nobody reads, and the check belongs next to it.
    private var updateBar: some View {
        HStack(spacing: 6) {
            Text("v\(TrailwardenVersion.installed)")
                .font(Tokens.Typography.font(.codeSmall))
                .foregroundStyle(Tokens.Palette.tertiary)
            if let line = updateLine {
                Image(systemName: line.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(line.tint)
                Text(line.text)
                    .font(Tokens.Typography.font(.caption, weight: line.weight))
                    .foregroundStyle(line.tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let link = line.link {
                    Button(L(.releaseNotes)) {
                        NSWorkspace.shared.open(link)
                    }
                    .buttonStyle(.plain)
                    .font(Tokens.Typography.font(.caption, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accentText)
                }
            }
            Spacer(minLength: 2)
            Button {
                Task { await updates.check() }
            } label: {
                Text(L(.checkUpdates))
                    .font(Tokens.Typography.font(.caption, weight: .medium))
                    .foregroundStyle(updates.state == .checking ? Tokens.Palette.tertiary : Tokens.Palette
                        .accentText)
            }
            .buttonStyle(.plain)
            .disabled(updates.state == .checking)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.bottom, 9)
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
                            .font(Tokens.Typography.font(.title, weight: .semibold))
                            .foregroundStyle(Tokens.Palette.accentText)
                        Text(L(.severityCritical))
                            .font(Tokens.Typography.font(.callout))
                            .foregroundStyle(Tokens.Palette.secondary)
                        Text(time(critical.time))
                            .font(Tokens.Typography.font(.codeSmall))
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
                        .font(Tokens.Typography.font(.callout))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1)
                }
                if !critical.detail.isEmpty {
                    Text(critical.detail)
                        .font(Tokens.Typography.font(.codeSmall))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if model.snapshot.totalEvents == 0 {
                Text(model.isScanning ? model.scanLabel : L(.noDataYet))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                Text(L(.nothingRiskyToday))
                    .font(Tokens.Typography.font(.body))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.accentText)
                    .lineLimit(2)
            }
            if model.snapshot.messagesToday > 0 {
                Text(Lf(.messagesToday, [model.snapshot.messagesToday]))
                    .font(Tokens.Typography.font(.caption))
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
                    .font(Tokens.Typography.font(.callout))
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

    /// A row opens the timeline on the event it describes.
    private func actionRow(_ item: ActivityItem) -> some View {
        Button {
            model.openEvent(item.id, in: item.sessionID)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(time(item.time))
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.tertiary)
                    .frame(width: 74, alignment: .leading)
                Text(item.label)
                    .font(Tokens.Typography.font(.codeSmall, weight: .medium))
                    .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                Text(item.detail)
                    .font(Tokens.Typography.font(.caption))
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
                tint: Tokens.Palette.accentText, weight: .medium, link: feed.url)
        case .failed:
            return UpdateLine(
                icon: "exclamationmark.triangle", text: L(.updateCheckFailed),
                tint: Tokens.Palette.secondary, weight: .regular, link: nil)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            footerButton(L(.openDashboard), tint: Tokens.Palette.accentText, weight: .medium) {
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
                    .font(Tokens.Typography.font(.codeSmall, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accentText)
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
                .font(Tokens.Typography.font(.body))
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
                .font(Tokens.Typography.font(.body, weight: weight))
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
