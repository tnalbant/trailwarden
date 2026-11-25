// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// The rules window: every rule with its state, its severity, the reason it
/// fires, how many events it currently hits, plus the mutes that silence it.
struct RulesView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage(TechnicalDetails.storageKey) private var technical = false
    @ObservedObject var model: AppModel
    @State private var rescoping: Allowance?
    @State private var glob = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ruleList
            Hairline()
            allowanceList
            Hairline()
            footer
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
        .onAppear {
            model.loadRules()
            if model.rulesDirty {
                Task { await model.reapplyRules() }
            }
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

            if technical {
                Text(rule.id)
                    .font(Tokens.Typography.font(.code, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? Tokens.Palette.ink : Tokens.Palette.secondary)
                    .fixedSize()
                    .frame(minWidth: Tokens.Metrics.scaled(26), alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.localizedTitle(LocalizationStore.current))
                    .font(Tokens.Typography.font(.body, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? Tokens.Palette.ink : Tokens.Palette.secondary)
                if let examples = rule.examples, !technical {
                    exampleLine(L(.ruleExamplesMatch), examples.matches)
                    exampleLine(L(.ruleExamplesIgnore), examples.ignores)
                } else {
                    Text(ruleMatchSummary(rule))
                        .font(Tokens.Typography.font(.codeSmall))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
                Picker(L(.severityPickerLabel), selection: severityBinding(rule)) {
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

    /// Examples are shown as written; a rule's placeholders (`{{NAME}}`) stay
    /// placeholders.
    @ViewBuilder
    private func exampleLine(_ title: String, _ samples: [String]) -> some View {
        if !samples.isEmpty {
            Text("\(title): \(samples.prefix(2).joined(separator: " · "))")
                .font(Tokens.Typography.font(.codeSmall))
                .foregroundStyle(Tokens.Palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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

    // MARK: - Allowances

    private var allowanceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: L(.mutedRules))
                Spacer()
                Text("\(model.allowances.count)")
                    .font(Tokens.Typography.font(.codeSmall))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            if model.allowances.isEmpty {
                Text(L(.noMutes))
                    .font(Tokens.Typography.font(.callout))
                    .foregroundStyle(Tokens.Palette.secondary)
            } else {
                ForEach(model.allowances) { allowance in
                    allowanceRow(allowance)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func allowanceName(_ allowance: Allowance) -> String {
        guard !technical else { return allowance.ruleId }
        let rule = model.rules.first { $0.id == allowance.ruleId }
        return rule?.localizedTitle(LocalizationStore.current) ?? allowance.ruleId
    }

    private func allowanceRow(_ allowance: Allowance) -> some View {
        HStack(spacing: 8) {
            Text(allowanceName(allowance))
                .font(Tokens.Typography.font(.codeSmall, weight: .medium))
                .foregroundStyle(Tokens.Palette.accentText)
            Text(scopeKind(allowance.scope))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
            Text(scopeValue(allowance.scope))
                .font(Tokens.Typography.font(.codeSmall))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Menu(L(.scopeEditLabel)) {
                Button(L(.scopeEditPattern)) {
                    glob = allowance.patternPrefill
                    rescoping = allowance
                }
                Button(L(.scopeEditEverywhere)) {
                    Task { await rescope(allowance, to: .everywhere) }
                }
                .disabled(allowance.scope == .everywhere)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(Tokens.Typography.font(.caption))
            .accessibilityLabel(L(.scopeEditLabel))
            Menu(remainingText(allowance)) {
                ForEach(AllowanceDuration.allCases, id: \.self) { duration in
                    Button(AllowSheet.name(of: duration)) {
                        let now = Date()
                        Task {
                            await model.allow(Allowance(
                                id: allowance.id,
                                ruleId: allowance.ruleId,
                                scope: allowance.scope,
                                until: duration.until(from: now),
                                created: allowance.created))
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(Tokens.Typography.font(.caption))
            .accessibilityLabel(L(.allowDurationLabel))
            .accessibilityValue(remainingText(allowance))
            Button(L(.removeMute)) {
                Task { await model.removeAllowance(allowance) }
            }
            .buttonStyle(.plain)
            .font(Tokens.Typography.font(.caption, weight: .medium))
            .foregroundStyle(Tokens.Palette.accentText)
        }
        .accessibilityElement(children: .contain)
        .popover(isPresented: Binding(
            get: { rescoping?.id == allowance.id },
            set: {
                if !$0 {
                    rescoping = nil
                }
            })) {
                globEditor
        }
    }

    private func rescope(_ allowance: Allowance, to scope: AllowanceScope) async {
        let moved = allowance.rescoped(to: scope)
        guard moved.id != allowance.id else { return }
        if await model.allow(moved) {
            await model.removeAllowance(allowance)
        }
    }

    private var globEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L(.allowPatternLabel), text: $glob)
                .textFieldStyle(.roundedBorder)
                .font(Tokens.Typography.font(.code))
                .accessibilityLabel(L(.allowPatternLabel))
                .frame(width: Tokens.Metrics.scaled(300))
            Text(L(.allowPatternHint))
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
            HStack {
                Spacer()
                Button(L(.cancel)) { rescoping = nil }
                    .keyboardShortcut(.cancelAction)
                Button(L(.scopeEditApply)) {
                    guard let target = rescoping else { return }
                    let pattern = glob.trimmingCharacters(in: .whitespaces)
                    rescoping = nil
                    Task { await rescope(target, to: .pattern(glob: pattern)) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(glob.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    private func scopeKind(_ scope: AllowanceScope) -> String {
        switch scope {
        case .command: L(.kindCommand)
        case .projectRule: L(.kindProject)
        case .pattern: L(.kindPattern)
        case .everywhere: L(.kindEverywhere)
        }
    }

    private func scopeValue(_ scope: AllowanceScope) -> String {
        switch scope {
        case let .command(command): command
        case let .projectRule(project): technical ? project : AllowSheet.folderName(project)
        case let .pattern(glob): glob
        case .everywhere: L(.allowEverywhereValue)
        }
    }

    private func remainingText(_ allowance: Allowance) -> String {
        guard let until = allowance.until else { return L(.allowForeverRemaining) }
        let days = Int(ceil(until.timeIntervalSinceNow / 86400))
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
