// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// The right column: what exactly happened, why it was flagged, and the text the
/// agent actually ran.
///
/// Commands wrap. They used to scroll sideways to stay on one line, which meant a
/// long command could only be read one screen-width at a time while the column
/// below it sat empty.
struct EventDetailView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    let event: Event
    var onMute: ((RiskHit, Event) -> Void)?
    /// Where to look up other agents' work on the same file.
    var databaseURL: URL?
    var onOpen: ((Event) -> Void)?
    @State private var copiedResume = false

    @State private var copiedField: String?

    private var diff: [DiffLine]? {
        DiffExtractor.diff(in: event.command ?? event.preview ?? "")
    }

    private var resumeCommand: String? {
        ResumeCommand.command(agent: event.agent, sessionId: event.sessionId, cwd: event.cwd)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !event.risk.isEmpty {
                        riskSection
                    }
                    if let command = event.command {
                        textSection(L(.labelCommand), command, field: "command")
                    }
                    if let preview = event.preview, event.command == nil {
                        textSection(L(.labelText), preview, field: "preview")
                    }
                    if let diff {
                        diffSection(diff)
                    }
                    if !event.paths.isEmpty {
                        pathsSection
                    }
                    if let databaseURL, let path = event.paths.first {
                        FileNeighborsView(event: event, path: path, databaseURL: databaseURL, onOpen: onOpen)
                            .id(event.id)
                    }
                    if let raw = event.rawJSON {
                        rawSection(raw)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Pinned: the one action this pane offers should not sit wherever the
            // text happens to end, leaving the rest of the column empty below it.
            if let resumeCommand {
                Hairline()
                resumeSection(resumeCommand)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Tokens.Palette.paper)
            }
        }
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
    }

    // MARK: - Header

    /// One compact block instead of four loose lines: who, what, where, when.
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(EventFormatting.agentLabel(event.agent))
                    .font(Tokens.Typography.mono(9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Tokens.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(event.tool ?? event.kind.rawValue)
                    .font(Tokens.Typography.mono(10, weight: .medium))
                Spacer(minLength: 6)
                Text(EventFormatting.stamp(event.ts))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Sessions.shortID(event.sessionId))
                    .font(Tokens.Typography.mono(9))
                    .foregroundStyle(Tokens.Palette.secondary)
                if let cwd = event.cwd {
                    Text(ProjectName.display(cwd))
                        .font(Tokens.Typography.mono(9))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.surface.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Metrics.radius))
    }

    // MARK: - Resume

    /// The one action people ask a history browser for: carry on from here.
    private func resumeSection(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: L(.resumeSession))
            HStack(alignment: .top, spacing: 8) {
                Text(command)
                    .font(Tokens.Typography.mono(9.5))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Button(copiedResume ? L(.copied) : L(.copy)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedResume = true
                }
                .buttonStyle(.plain)
                .font(Tokens.Typography.text(10, weight: .medium))
                .foregroundStyle(Tokens.Palette.accent)
            }
        }
    }

    // MARK: - Sections

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: L(.whyFlagged))
            ForEach(event.risk, id: \.ruleId) { hit in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(hit.ruleId)
                        .font(Tokens.Typography.mono(9.5, weight: .medium))
                        .foregroundStyle(hit.severity.tint)
                    Text(hit.localizedMessage(LocalizationStore.current))
                        .font(Tokens.Typography.text(10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let onMute {
                        Button(L(.muteThirtyDays)) { onMute(hit, event) }
                            .buttonStyle(.plain)
                            .font(Tokens.Typography.text(9, weight: .medium))
                            .foregroundStyle(Tokens.Palette.accent)
                            .help(L(.muteThirtyDaysHint))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Metrics.radius))
    }

    /// Everything wraps. A command is the reason the window exists, so it gets the
    /// whole column and as many lines as it needs.
    private func textSection(_ title: String, _ text: String, field: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: title)
                Spacer()
                copyButton(field, text)
            }
            Text(text)
                .font(Tokens.Typography.mono(10.5))
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Tokens.Palette.surface.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func diffSection(_ lines: [DiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: L(.labelDiff))
                Spacer()
                copyButton("diff", lines.map { prefix(for: $0.kind) + $0.text }.joined(separator: "\n"))
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(prefix(for: line.kind) + line.text)
                        .font(Tokens.Typography.mono(10))
                        .foregroundStyle(color(for: line.kind))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            }
            .padding(.vertical, 4)
            .background(Tokens.Palette.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: L(.labelPaths))
            ForEach(event.paths, id: \.self) { path in
                Text(ProjectName.display(path))
                    .font(Tokens.Typography.mono(9.5))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rawSection(_ raw: String) -> some View {
        DisclosureGroup {
            Text(raw)
                .font(Tokens.Typography.mono(9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        } label: {
            SectionLabel(text: L(.labelRaw))
        }
    }

    private func copyButton(_ field: String, _ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedField = field
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copiedField == field {
                    copiedField = nil
                }
            }
        } label: {
            Text(copiedField == field ? L(.copied) : L(.copy))
                .font(Tokens.Typography.text(9.5, weight: .medium))
                .foregroundStyle(Tokens.Palette.accent)
        }
        .buttonStyle(.plain)
    }

    private func prefix(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition: "+"
        case .removal: "-"
        case .context: " "
        case .header: ""
        }
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: Tokens.Palette.diffAddition
        case .removal: Tokens.Palette.diffRemoval
        case .header: Tokens.Palette.diffHeader
        case .context: Tokens.Palette.ink.opacity(0.78)
        }
    }
}

/// "Who else touched this file?" — the other sessions that changed, read or
/// named the same path, so two agents working on one file are visible from
/// either side.
private struct FileNeighborsView: View {
    let event: Event
    let path: String
    let databaseURL: URL
    var onOpen: ((Event) -> Void)?
    @State private var touches: [FileTouch]?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: L(.whoTouched))
            if let touches {
                if touches.isEmpty {
                    Text(L(.whoNone))
                        .font(Tokens.Typography.text(10))
                        .foregroundStyle(Tokens.Palette.secondary)
                }
                ForEach(touches) { touch in
                    Button {
                        onOpen?(touch.event)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(EventFormatting.agentLabel(touch.event.agent))
                                .font(Tokens.Typography.mono(9, weight: .medium))
                            Text(touch.action.label(LocalizationStore.current))
                                .font(Tokens.Typography.mono(9))
                                .foregroundStyle(touch.action == .changed
                                    ? Tokens.Palette.accent
                                    : Tokens.Palette.secondary)
                            Text(EventFormatting.stamp(touch.event.ts))
                                .font(Tokens.Typography.mono(9))
                                .foregroundStyle(Tokens.Palette.tertiary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Tokens.Palette.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .task {
            let url = databaseURL
            let target = FileHistory.Target(
                absolute: path.hasPrefix("~")
                    ? NSHomeDirectory() + path.dropFirst()
                    : path,
                isDirectory: false)
            let session = event.sessionId
            touches = await Task.detached(priority: .userInitiated) { () -> [FileTouch] in
                guard let store = try? EventStore(url: url),
                      let found = try? FileHistory.touches(of: target, in: store, limit: 40)
                else { return [] }
                return Array(found.filter { $0.event.sessionId != session }.prefix(6))
            }.value
        }
    }
}
