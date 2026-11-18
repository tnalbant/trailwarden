// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// "What happened today", grouped by project. Actions are the rows; a chat turn
/// is a quiet line underneath, because it explains the action but is not the
/// thing the reader came for.
struct FeedView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: FeedModel
    /// Clicking a row hands the session to the timeline, which already knows how
    /// to show the full event.
    var onOpenSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            if let error = model.errorMessage {
                Text(error)
                    .font(Tokens.Typography.text(11))
                    .foregroundStyle(Tokens.Palette.accent)
                    .padding(.horizontal, Tokens.Metrics.gutter)
                    .padding(.vertical, 8)
            }
            ScrollView {
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
            .background(Tokens.Palette.paper)
        }
        .background(Tokens.Palette.paper)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(dateLabel)
                .font(Tokens.Typography.serif(15, weight: .semibold))
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
                .font(Tokens.Typography.text(12))
            Text(L(.noEventsHint))
                .font(Tokens.Typography.text(10.5))
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
                    .font(Tokens.Typography.text(11.5, weight: .medium))
                Text("\(section.items.count)")
                    .font(Tokens.Typography.text(9))
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
            onOpenSession(item.sessionID)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(time(item.time))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(Tokens.Palette.tertiary)
                    .fixedSize()
                    .frame(width: 84, alignment: .leading)

                Text(item.label)
                    .font(Tokens.Typography.mono(9))
                    .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Tokens.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: 86, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.detail)
                        .font(Tokens.Typography.text(11))
                        .foregroundStyle(item.isMessage ? Tokens.Palette.secondary : Tokens.Palette.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let rule = item.ruleLine(LocalizationStore.current), let severity = item.severity {
                        Text(rule)
                            .font(Tokens.Typography.text(9.5))
                            .foregroundStyle(Tokens.Palette.severity(severity))
                    }
                }

                if let severity = item.severity {
                    Circle()
                        .fill(Tokens.Palette.severity(severity))
                        .frame(width: 6, height: 6)
                        .padding(.top, 3)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.ruleLine(LocalizationStore.current) ?? item.detail)
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
