// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// "What happened today", grouped by project. Actions are the rows; a chat turn
/// is a quiet line underneath, because it explains the action but is not the
/// thing the reader came for.
struct FeedView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage(TechnicalDetails.storageKey) private var technical = false
    @ObservedObject var model: FeedModel
    /// Clicking a row hands the event to the timeline, which shows it in full.
    var onOpen: (ActivityItem) -> Void
    /// Inside the inbox the feed has no scroll view or header of its own.
    var embedded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                header
                Hairline()
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(Tokens.Typography.font(.body))
                    .foregroundStyle(Tokens.Palette.accentText)
                    .padding(.horizontal, Tokens.Metrics.gutter)
                    .padding(.vertical, 8)
            }
            if embedded {
                sections
            } else {
                ScrollView {
                    sections
                }
                .background(Tokens.Palette.paper)
            }
        }
        .background(Tokens.Palette.paper)
    }

    private var sections: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            if model.sections.isEmpty {
                emptyState
            }
            ForEach(model.sections) { section in
                sectionView(section)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(dateLabel)
                .font(Tokens.Typography.font(.subtitle, weight: .semibold))
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.noEventsInRange))
                .font(Tokens.Typography.font(.body))
            Text(L(.noEventsHint))
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
        }
        .padding(.top, 40)
    }

    private func sectionView(_ section: FeedModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.secondary)
                Text(section.title)
                    .font(Tokens.Typography.font(.body, weight: .medium))
                Text("\(section.items.count)")
                    .font(Tokens.Typography.font(.caption))
                    .foregroundStyle(Tokens.Palette.secondary)
                if section.criticalCount > 0 {
                    Circle()
                        .fill(Tokens.Palette.severity(.critical))
                        .frame(width: 5, height: 5)
                }
                Spacer()
            }
            Hairline()
            VStack(alignment: .leading, spacing: 3) {
                ForEach(section.items) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: ActivityItem) -> some View {
        Button {
            onOpen(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(time(item.time))
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.tertiary)
                    .fixedSize()
                    .frame(minWidth: Tokens.Metrics.scaled(84), alignment: .leading)

                HStack(spacing: 4) {
                    Image(systemName: item.verb.symbolName)
                        .font(Tokens.Typography.font(.caption))
                        .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                        .accessibilityHidden(true)
                    if technical {
                        Text(item.label)
                            .font(Tokens.Typography.font(.codeSmall))
                            .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Tokens.Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .fixedSize()
                .frame(minWidth: Tokens.Metrics.scaled(technical ? 110 : 20), alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.summary(LocalizationStore.current))
                        .font(Tokens.Typography.font(.body))
                        .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let severity = item.severity, let title = item.ruleTitle(LocalizationStore.current) {
                        Text(TechnicalDetails.badge(
                            title: title,
                            ruleId: item.ruleId ?? "",
                            technical: technical))
                            .font(Tokens.Typography.font(.caption, weight: .medium))
                            .foregroundStyle(severity.textTint)
                    }
                    if item.outsideProject {
                        Text(L(.outsideProject))
                            .font(Tokens.Typography.font(.caption))
                            .foregroundStyle(Tokens.Palette.secondary)
                    }
                }

                if let severity = item.severity {
                    Circle()
                        .fill(Tokens.Palette.severity(severity))
                        .frame(width: 6, height: 6)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(RowAccessibility.label(
                severity: item.severity,
                summary: item.summary(LocalizationStore.current),
                agent: EventFormatting.agentLabel(item.agent),
                time: time(item.time)))
        }
        .buttonStyle(.plain)
        .help(item.ruleLine(LocalizationStore.current) ?? item.summary(LocalizationStore.current))
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.current.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: Date())
    }

    private func time(_ date: Date) -> String {
        EventFormatting.stamp(date)
    }
}
