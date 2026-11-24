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

/// One line of the event stream: time, agent, tool, the command or text, and the
/// worst rule hit as a coloured strip on the left.
struct EventRowView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    let event: Event
    var selected = false

    private var worst: Severity? {
        event.risk.map(\.severity).max()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(worst?.tint ?? Color.clear)
                .frame(width: 2.5)

            HStack(alignment: .top, spacing: 9) {
                Text(EventFormatting.stamp(event.ts))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(Tokens.Palette.secondary)
                    .fixedSize()
                    .frame(width: 88, alignment: .leading)

                Text(EventFormatting.agentLabel(event.agent))
                    .font(Tokens.Typography.mono(8.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Tokens.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.tool ?? event.kind.rawValue)
                            .font(Tokens.Typography.mono(9.5, weight: .medium))
                        ForEach(event.risk, id: \.ruleId) { hit in
                            Text("\(hit.ruleId) \(LocalizationStore.current.severity(hit.severity))")
                                .font(Tokens.Typography.text(8.5, weight: .medium))
                                .foregroundStyle(hit.severity.textTint)
                        }
                    }
                    Text(event.preview ?? event.command ?? "—")
                        .font(Tokens.Typography.mono(10))
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
    }
}
