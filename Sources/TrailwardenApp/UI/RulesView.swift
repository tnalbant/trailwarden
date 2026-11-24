// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The rules window: every rule with its state, its severity, the reason it
/// fires, how many events it currently hits, plus the mutes that silence it.
struct RulesView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ruleList
            Hairline()
            muteList
            Hairline()
            footer
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
        .onAppear {
            model.loadRules()
            Task { await model.reapplyRules() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(.windowRules))
                .font(Tokens.Typography.font(.title, weight: .semibold))
            Text(L(.rulesIntro))
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Rules

    private var ruleList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.rules) { rule in
                    ruleRow(rule)
                    Hairline()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await model.updateRule(rule.id, enabled: !rule.isEnabled) }
            } label: {
                Image(systemName: rule.isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(rule.isEnabled ? Tokens.Palette.accent : Tokens.Palette.secondary)
            }
            .buttonStyle(.plain)
            .help(rule.isEnabled ? L(.disableRule) : L(.enableRule))

            Text(rule.id)
                .font(Tokens.Typography.font(.code, weight: .medium))
                .foregroundStyle(rule.isEnabled ? Tokens.Palette.ink : Tokens.Palette.secondary)
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.localizedTitle(LocalizationStore.current))
                    .font(Tokens.Typography.font(.body, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? Tokens.Palette.ink : Tokens.Palette.secondary)
                Text(ruleMatchSummary(rule))
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rule.localizedMessage(LocalizationStore.current))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Lf(.ruleHits, [model.ruleHitCounts[rule.id] ?? 0]))
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
                Picker("", selection: severityBinding(rule)) {
                    ForEach([Severity.info, Severity.warn, Severity.critical], id: \.self) { severity in
                        Text(LocalizationStore.current.severity(severity)).tag(severity)
                    }
                }
                .labelsHidden()
                .frame(width: 92)
                .disabled(!rule.isEnabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .opacity(rule.isEnabled ? 1 : 0.62)
    }

    private func severityBinding(_ rule: Rule) -> Binding<Severity> {
        Binding(
            get: { rule.severity },
            set: { severity in
                Task { await model.updateRule(rule.id, severity: severity) }
            })
    }

    private func ruleMatchSummary(_ rule: Rule) -> String {
        var parts: [String] = []
        let tools = rule.match.allTools
        if !tools.isEmpty {
            parts.append(Lf(.ruleTool, [tools.joined(separator: ", ")]))
        }
        for regex in rule.match.allCommandPatterns {
            parts.append("/\(regex)/")
        }
        let globs = rule.match.allPathGlobs
        if !globs.isEmpty {
            parts.append(globs.joined(separator: " "))
        }
        return parts.isEmpty ? L(.ruleMatchesAll) : parts.joined(separator: " · ")
    }

    // MARK: - Mutes

    private var muteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: L(.mutedRules))
                Spacer()
                Text("\(model.mutes.count)")
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            if model.mutes.isEmpty {
                Text(L(.noMutes))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                ForEach(model.mutes) { mute in
                    HStack(spacing: 8) {
                        Text(mute.ruleId)
                            .font(Tokens.Typography.font(.codeSmall, weight: .medium))
                            .foregroundStyle(Tokens.Palette.accentText)
                        Text(mute.target)
                            .font(Tokens.Typography.font(.codeSmall))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(remainingDays(mute))
                            .font(Tokens.Typography.font(.caption))
                            .foregroundStyle(Tokens.Palette.secondary)
                        Button(L(.removeMute)) {
                            Task { await model.removeMute(mute) }
                        }
                        .buttonStyle(.plain)
                        .font(Tokens.Typography.font(.caption, weight: .medium))
                        .foregroundStyle(Tokens.Palette.accentText)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remainingDays(_ mute: Mute) -> String {
        let days = Int(ceil(mute.until.timeIntervalSinceNow / 86400))
        return days > 0 ? Lf(.daysLeft, [days]) : L(.muteExpired)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.isReapplying {
                ProgressView().controlSize(.small)
                Text(L(.reapplying))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else if let status = model.ruleStatus {
                Text(status)
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Spacer()
            Button {
                Task { await model.reapplyRules() }
            } label: {
                Text(L(.reapply))
                    .font(Tokens.Typography.font(.callout, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accentText)
            }
            .buttonStyle(.plain)
            .disabled(model.isReapplying)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
