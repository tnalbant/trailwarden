// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// The report card: a month of agent work on one page. It is what a new reader
/// sees after the first scan — the answer to "what have these agents been doing
/// on my Mac?" — and the page people screenshot.
struct ReportView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var router: DashboardRouter
    @State private var days = 30
    @State private var card: ReportCard?
    @State private var copied = false
    /// A snapshot renders without a scroll view, which an image renderer cannot draw.
    private let scrolls: Bool

    init(model: AppModel, preloaded: ReportCard? = nil, scrolls: Bool = true) {
        self.model = model
        self.scrolls = scrolls
        _card = State(initialValue: preloaded)
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { page }
            } else {
                page
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
        .tint(Tokens.Palette.accent)
        .task(id: days) { await load() }
        .onChange(of: model.snapshot) { _, _ in
            Task { await load() }
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let card {
                if card.isEmpty {
                    Text(L(.reportEmpty))
                        .font(Tokens.Typography.font(.body))
                        .foregroundStyle(Tokens.Palette.secondary)
                } else {
                    content(card)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Lf(.reportTitle, [days]))
                    .font(Tokens.Typography.font(.display, weight: .semibold))
                if let card, !card.isEmpty {
                    Text(Lf(.reportWork, [card.toolCalls, card.sessions, card.projects]))
                        .font(Tokens.Typography.font(.body))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
            }
            Spacer()
            if !scrolls {
                // Snapshot: the segmented control does not render off screen.
                Text("\(days)d")
                    .font(Tokens.Typography.font(.code))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Picker(L(.rangePickerLabel), selection: $days) {
                Text(L(.rangeWeek)).tag(7)
                Text(L(.rangeMonth)).tag(30)
                Text(L(.range90Days)).tag(90)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .opacity(scrolls ? 1 : 0)
            .frame(width: scrolls ? 210 : 0)
            Button {
                copySummary()
            } label: {
                Label(
                    copied ? L(.copied) : L(.reportCopySummary),
                    systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(Tokens.Typography.font(.body, weight: .medium))
            }
            .disabled(card?.isEmpty ?? true)
            .help(L(.reportSummaryHint))
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func content(_ card: ReportCard) -> some View {
        tiles(card)
        Hairline()
        HStack(alignment: .top, spacing: 28) {
            agents(card)
                .frame(maxWidth: .infinity, alignment: .leading)
            hotFiles(card)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        Hairline()
        findings(card)
        if !card.rules.isEmpty {
            Hairline()
            rules(card)
        }
        Text(L(.reportSummaryHint))
            .font(Tokens.Typography.font(.callout))
            .foregroundStyle(Tokens.Palette.tertiary)
    }

    private func criticalTint(_ card: ReportCard) -> Color? {
        card.critical > 0 ? Tokens.Palette.accentText : nil
    }

    private func tiles(_ card: ReportCard) -> some View {
        HStack(spacing: 10) {
            tile(card.commands, L(.reportCommands))
            tile(card.edits, L(.reportEdits))
            tile(card.reads, L(.reportReads))
            tile(card.filesChanged, L(.reportFilesChanged))
            tile(card.critical, L(.severityCritical), tint: criticalTint(card))
            tile(card.warnings, L(.severityWarning))
        }
    }

    private func tile(_ value: Int, _ label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(Tokens.Typography.font(.display, weight: .semibold))
                .foregroundStyle(tint ?? Tokens.Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Metrics.radius))
    }

    private func agents(_ card: ReportCard) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: L(.reportByAgent))
            let top = max(card.agents.map(\.toolCalls).max() ?? 1, 1)
            ForEach(card.agents) { share in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(share.agent.displayName)
                            .font(Tokens.Typography.font(.body, weight: .medium))
                        Spacer()
                        Text("\(share.toolCalls.formatted()) · \(share.sessions) \(L(.sessions))")
                            .font(Tokens.Typography.font(.code))
                            .foregroundStyle(Tokens.Palette.secondary)
                    }
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Tokens.Palette.ink.opacity(0.75))
                            .frame(width: max(4, proxy.size.width * CGFloat(share.toolCalls) / CGFloat(top)))
                    }
                    .frame(height: 5)
                }
            }
        }
    }

    private func hotFiles(_ card: ReportCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(.reportHotFiles))
            ForEach(card.hotFiles) { file in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(file.changes)")
                        .font(Tokens.Typography.font(.code, weight: .semibold))
                        .fixedSize()
                        .frame(minWidth: Tokens.Metrics.scaled(30), alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((file.path as NSString).lastPathComponent)
                            .font(Tokens.Typography.font(.code))
                            .lineLimit(1)
                        Text(ProjectName.display((file.path as NSString).deletingLastPathComponent))
                            .font(Tokens.Typography.font(.codeSmall))
                            .foregroundStyle(Tokens.Palette.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 4)
                    Text(file.agents.map(EventFormatting.agentLabel).joined(separator: " · "))
                        .font(Tokens.Typography.font(.codeSmall))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
            }
        }
    }

    private func findings(_ card: ReportCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(.reportWorthALook))
            if card.worthALook.isEmpty {
                Text(L(.reportNoFindings))
                    .font(Tokens.Typography.font(.body))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            ForEach(card.worthALook) { event in
                Button {
                    model.openEvent(event.id, in: event.sessionId)
                    router.show(.timeline)
                    openWindow(id: "main")
                } label: {
                    findingRow(event)
                }
                .buttonStyle(.plain)
                .help(L(.reportOpen))
            }
        }
    }

    private func findingRow(_ event: Event) -> some View {
        let worst = event.activeRisk.max { $0.severity < $1.severity }
        let localizer = LocalizationStore.current
        let title = worst
            .flatMap { RuleLocalization.text(forRule: $0.ruleId, language: localizer.language)?.title }
            ?? worst?.ruleId ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Tokens.Palette.severity(worst?.severity ?? .info))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(Tokens.Typography.font(.body, weight: .semibold))
                    Text("\(event.agent.displayName) · \(EventFormatting.stamp(event.ts))")
                        .font(Tokens.Typography.font(.codeSmall))
                        .foregroundStyle(Tokens.Palette.secondary)
                    if let project = ActivityDigest.project(from: event.cwd) {
                        Text(project)
                            .font(Tokens.Typography.font(.codeSmall))
                            .foregroundStyle(Tokens.Palette.tertiary)
                    }
                }
                Text((event.command ?? event.paths.first ?? event.preview ?? "")
                    .replacingOccurrences(of: "\n", with: " ⏎ "))
                    .font(Tokens.Typography.font(.code))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Tokens.Palette.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Tokens.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func rules(_ card: ReportCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(.reportRules))
            let localizer = LocalizationStore.current
            FlowRow(spacing: 6) {
                ForEach(card.rules) { count in
                    let title = RuleLocalization.text(forRule: count.ruleId, language: localizer.language)?
                        .title
                        ?? count.ruleId
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Tokens.Palette.severity(count.severity))
                            .frame(width: 6, height: 6)
                        Text("\(title) ×\(count.count)")
                            .font(Tokens.Typography.font(.callout))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Tokens.Palette.surface)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        let url = model.databaseURL
        let span = days
        let loaded = await Task.detached(priority: .userInitiated) { () -> ReportCard? in
            guard let store = try? EventStore(url: url) else { return nil }
            return try? ReportCard.build(from: store, days: span)
        }.value
        card = loaded ?? ReportCard(since: Date(), until: Date())
    }

    private func copySummary() {
        guard let card else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            card.shareableSummary(localizer: LocalizationStore.current),
            forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// Lays chips out left to right and wraps to the next line.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ())
    {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
