// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The findings that have not been looked at, worst first, with today's
/// activity underneath. Every row is one element for VoiceOver; the four
/// actions are ordinary buttons, reachable with the keyboard.
struct InboxView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage(TechnicalDetails.storageKey) private var technical = false
    @ObservedObject var model: InboxModel
    @ObservedObject var feed: FeedModel
    @ObservedObject var app: AppModel
    var onOpenSession: (String, String?) -> Void
    var onOpenActivity: (ActivityItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let backlog = model.backlog {
                    banner(backlog)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(Tokens.Typography.font(.body))
                        .foregroundStyle(Tokens.Palette.accentText)
                        .padding(.horizontal, Tokens.Metrics.gutter)
                        .padding(.vertical, 8)
                }
                if model.findings.isEmpty {
                    Text(L(.inboxEmpty))
                        .font(Tokens.Typography.font(.body))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .padding(.horizontal, Tokens.Metrics.gutter)
                        .padding(.vertical, 16)
                }
                ForEach(model.findings) { finding in
                    row(finding)
                    Hairline()
                }
                Text(L(.inboxActivityHeading))
                    .font(Tokens.Typography.font(.subtitle, weight: .semibold))
                    .padding(.horizontal, Tokens.Metrics.gutter)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                FeedView(model: feed, onOpen: onOpenActivity, embedded: true)
            }
        }
        .background(Tokens.Palette.paper)
        .onChange(of: model.findings.map(\.id)) { _, _ in
            app.refresh()
        }
    }

    // MARK: - Backlog banner

    private func banner(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Lf(.inboxBacklogTitle, [count]))
                .font(Tokens.Typography.font(.body, weight: .medium))
            HStack(spacing: 12) {
                Button(L(.inboxMarkAllReviewed)) {
                    model.resolveBacklog(markReviewed: true)
                }
                Button(L(.inboxShowThem)) {
                    model.resolveBacklog(markReviewed: false)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Tokens.Metrics.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.surface)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Rows

    private func row(_ finding: InboxFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(Tokens.Palette.severity(finding.severity))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(TechnicalDetails.badge(
                        title: title(finding),
                        ruleId: finding.ruleId,
                        technical: technical))
                        .font(Tokens.Typography.font(.body, weight: .semibold))
                        .foregroundStyle(finding.severity.textTint)
                    Spacer(minLength: 0)
                    Text(EventFormatting.stamp(finding.at))
                        .font(Tokens.Typography.font(.codeSmall))
                        .foregroundStyle(Tokens.Palette.tertiary)
                }
                Text(summary(finding))
                    .font(Tokens.Typography.font(.body))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(context(finding))
                    .font(Tokens.Typography.font(.caption))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel(finding))
            actions(finding)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 10)
    }

    private func actions(_ finding: InboxFinding) -> some View {
        HStack(spacing: 8) {
            Button(L(.inboxReviewed)) {
                model.review(finding, as: .reviewed)
            }
            if let project = projectPath(finding) {
                Button(L(.inboxExpectedHere)) {
                    Task {
                        let stored = await app.allow(Allowance(
                            ruleId: finding.ruleId,
                            scope: .projectRule(project: project),
                            until: nil))
                        if stored {
                            model.review(finding, as: .expected)
                        }
                    }
                }
            }
            Button(L(.inboxFalseAlarm)) {
                model.review(finding, as: .falsePositive)
            }
            if case let .event(event) = finding.source {
                Button(L(.inboxOpen)) {
                    onOpenSession(event.sessionId, event.id)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Text

    private func title(_ finding: InboxFinding) -> String {
        RuleLocalization.text(forRule: finding.ruleId, language: LocalizationStore.current.language)?
            .title ?? finding.ruleId
    }

    private func summary(_ finding: InboxFinding) -> String {
        switch finding.source {
        case let .event(event):
            EventPresentation.summary(for: event, localizer: LocalizationStore.current)
        case let .file(path, line, _):
            line.map { "\(path), \(Lf(.inboxLine, [$0]))" } ?? path
        }
    }

    private func projectPath(_ finding: InboxFinding) -> String? {
        guard case let .event(event) = finding.source else { return nil }
        return event.cwd
    }

    private func context(_ finding: InboxFinding) -> String {
        switch finding.source {
        case let .event(event):
            [EventFormatting.agentLabel(event.agent), event.cwd.map(Self.projectName)]
                .compactMap(\.self)
                .joined(separator: " · ")
        case let .file(_, _, preview):
            preview
        }
    }

    private func spokenLabel(_ finding: InboxFinding) -> String {
        [
            LocalizationStore.current.severity(finding.severity),
            title(finding),
            summary(finding),
            context(finding),
            EventFormatting.stamp(finding.at)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private static func projectName(_ cwd: String) -> String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
