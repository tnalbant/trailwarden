// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import SwiftUI
import TrailwardenCore

/// One finding the reader is about to allow.
struct AllowRequest: Identifiable {
    let hit: RiskHit
    let event: Event
    var id: String {
        "\(event.id)|\(hit.ruleId)"
    }
}

/// Allow… sheet: where the allowance reaches, for how long, and a pattern the
/// reader can edit. The raw target appears only with technical details on.
struct AllowSheet: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @AppStorage(TechnicalDetails.storageKey) private var technical = false
    let request: AllowRequest
    let ruleTitle: String
    var onAllow: (Allowance) -> Void
    var onCancel: () -> Void

    @State private var scopeIndex = 0
    @State private var glob: String
    @State private var duration = AllowanceDuration.thirtyDays
    private let scopes: [AllowanceScope]

    init(
        request: AllowRequest,
        ruleTitle: String,
        onAllow: @escaping (Allowance) -> Void,
        onCancel: @escaping () -> Void)
    {
        self.request = request
        self.ruleTitle = ruleTitle
        self.onAllow = onAllow
        self.onCancel = onCancel
        let scopes = AllowanceChoice.scopes(for: request.event, hit: request.hit)
        self.scopes = scopes
        let initial = scopes.lazy.compactMap { scope -> String? in
            if case let .pattern(glob) = scope {
                glob
            } else {
                nil
            }
        }.first
        _glob = State(initialValue: initial ?? "")
    }

    private var selected: AllowanceScope {
        let scope = scopes[min(scopeIndex, scopes.count - 1)]
        if case .pattern = scope {
            return .pattern(glob: glob.trimmingCharacters(in: .whitespaces))
        }
        return scope
    }

    private var canAllow: Bool {
        if case let .pattern(glob) = selected {
            return !glob.isEmpty
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L(.allowSheetTitle))
                .font(Tokens.Typography.font(.heading))
                .accessibilityAddTraits(.isHeader)
            Text(TechnicalDetails.badge(title: ruleTitle, ruleId: request.hit.ruleId, technical: technical))
                .font(Tokens.Typography.font(.callout, weight: .medium))
                .foregroundStyle(Tokens.Palette.secondary)
            if !technical {
                Text(EventPresentation.summary(for: request.event, localizer: LocalizationStore.current))
                    .font(Tokens.Typography.font(.callout))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L(.allowScopeLabel))
                Picker(L(.allowScopeLabel), selection: $scopeIndex) {
                    ForEach(Array(scopes.enumerated()), id: \.offset) { index, scope in
                        Text(label(for: scope)).tag(index)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if case .pattern = scopes[min(scopeIndex, scopes.count - 1)] {
                    TextField(L(.allowPatternLabel), text: $glob)
                        .textFieldStyle(.roundedBorder)
                        .font(Tokens.Typography.font(.code))
                        .accessibilityLabel(L(.allowPatternLabel))
                    Text(L(.allowPatternHint))
                        .font(Tokens.Typography.font(.caption))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
                if technical, case let .command(target) = scopes[0] {
                    Text(target)
                        .font(Tokens.Typography.font(.codeSmall))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L(.allowDurationLabel))
                Picker(L(.allowDurationLabel), selection: $duration) {
                    ForEach(AllowanceDuration.allCases, id: \.self) { option in
                        Text(AllowSheet.name(of: option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Spacer()
                Button(L(.cancel), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L(.allowConfirm)) {
                    let now = Date()
                    onAllow(Allowance(
                        ruleId: request.hit.ruleId,
                        scope: selected,
                        until: duration.until(from: now),
                        created: now))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAllow)
            }
        }
        .padding(20)
        .frame(width: Tokens.Metrics.scaled(420))
    }

    private func label(for scope: AllowanceScope) -> String {
        switch scope {
        case .command: L(.scopeCommand)
        case let .projectRule(project): Lf(.scopeProject, [AllowSheet.folderName(project)])
        case .pattern: L(.scopePattern)
        case .everywhere: L(.scopeEverywhere)
        }
    }

    static func folderName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    static func name(of duration: AllowanceDuration) -> String {
        switch duration {
        case .oneDay: L(.durationOneDay)
        case .thirtyDays: L(.durationThirtyDays)
        case .forever: L(.durationForever)
        }
    }
}
