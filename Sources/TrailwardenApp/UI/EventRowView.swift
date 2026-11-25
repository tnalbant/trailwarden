// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

extension Severity {
    var tint: Color {
        switch self {
        case .critical: Tokens.Palette.accent
        case .warn: Tokens.Palette.severity(.warn)
        case .info: Tokens.Palette.secondary
        }
    }

    /// The tint for text: the terracotta accent is only for marks.
    var textTint: Color {
        self == .critical ? Tokens.Palette.accentText : tint
    }
}

/// The one sentence VoiceOver reads for a row: severity word (if any), summary,
/// agent, time. The visible severity strip and dot carry no extra information.
enum RowAccessibility {
    static func label(severity: Severity?, summary: String, agent: String, time: String) -> String {
        [severity.map { LocalizationStore.current.severity($0) }, summary, agent, time]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// One line of the event stream: time, agent, tool, the command or text, and the
/// worst rule hit as a coloured strip on the left.
struct EventRowView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage(TechnicalDetails.storageKey) private var technical = false
    let event: Event
    var selected = false

    private var worst: Severity? {
        event.activeRisk.map(\.severity).max()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(worst?.tint ?? Color.clear)
                .frame(width: 2.5)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 9) {
                Text(EventFormatting.stamp(event.ts))
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
                    .fixedSize()
                    .frame(minWidth: Tokens.Metrics.scaled(88), alignment: .leading)

                Text(EventFormatting.agentLabel(event.agent))
                    .font(Tokens.Typography.font(.codeSmall))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Tokens.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: EventPresentation.verb(for: event).symbolName)
                            .font(Tokens.Typography.font(.caption))
                            .foregroundStyle(Tokens.Palette.secondary)
                            .accessibilityHidden(true)
                        if technical {
                            Text(event.tool ?? event.kind.rawValue)
                                .font(Tokens.Typography.font(.codeSmall, weight: .medium))
                        }
                        ForEach(event.risk, id: \.ruleId) { hit in
                            if hit.allowed {
                                Text("\(badge(for: hit)) · \(L(.allowedBadge))")
                                    .font(Tokens.Typography.font(.caption))
                                    .foregroundStyle(Tokens.Palette.secondary)
                                    .accessibilityLabel(Lf(.allowedAccessibility, [badge(for: hit)]))
                            } else {
                                Text(badge(for: hit))
                                    .font(Tokens.Typography.font(.caption, weight: .medium))
                                    .foregroundStyle(hit.severity.textTint)
                            }
                        }
                        if EventPresentation.touchesOutsideProject(event) {
                            Text(L(.outsideProject))
                                .font(Tokens.Typography.font(.caption))
                                .foregroundStyle(Tokens.Palette.secondary)
                        }
                    }
                    Text(EventPresentation.summary(for: event, localizer: LocalizationStore.current))
                        .font(Tokens.Typography.font(.body))
                        .foregroundStyle(Tokens.Palette.ink.opacity(0.82))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 9)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
        }
        .background(selected ? Tokens.Palette.surface : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RowAccessibility.label(
            severity: worst,
            summary: EventPresentation.summary(for: event, localizer: LocalizationStore.current),
            agent: EventFormatting.agentLabel(event.agent),
            time: EventFormatting.stamp(event.ts)))
    }

    private func badge(for hit: RiskHit) -> String {
        TechnicalDetails.badge(
            title: EventPresentation.ruleTitle(hit, localizer: LocalizationStore.current),
            ruleId: hit.ruleId,
            technical: technical)
    }
}
