// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// The right column: what exactly happened, why it was flagged, and the text the
/// agent actually ran — never wrapped, so a one-line command stays one line.
struct EventDetailView: View {
    let event: Event
    var onMute: ((RiskHit, Event) -> Void)?

    @State private var copiedField: String?

    private var diff: [DiffLine]? {
        DiffExtractor.diff(in: event.command ?? event.preview ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !event.risk.isEmpty { riskSection }
                if let command = event.command {
                    textSection("Komut", command, field: "command", wraps: false)
                }
                if let preview = event.preview, event.command == nil {
                    textSection("Metin", preview, field: "preview", wraps: true)
                }
                if let diff { diffSection(diff) }
                if !event.paths.isEmpty { pathsSection }
                if let raw = event.rawJSON { rawSection(raw) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(EventFormatting.agentLabel(event.agent))
                    .font(Tokens.Typography.mono(9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Tokens.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(event.tool ?? event.kind.rawValue)
                    .font(Tokens.Typography.mono(9.5, weight: .medium))
                Spacer()
                Text(EventFormatting.time(event.ts))
                    .font(Tokens.Typography.mono(9.5))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            Text(Sessions.shortID(event.sessionId))
                .font(Tokens.Typography.mono(9))
                .foregroundStyle(Tokens.Palette.secondary)
            if let cwd = event.cwd {
                Text(ProjectName.display(cwd))
                    .font(Tokens.Typography.mono(9))
                    .foregroundStyle(Tokens.Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Neden işaretlendi")
            ForEach(event.risk, id: \.ruleId) { hit in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(hit.ruleId)
                        .font(Tokens.Typography.mono(9.5, weight: .medium))
                        .foregroundStyle(hit.severity.tint)
                    Text(hit.message)
                        .font(Tokens.Typography.text(10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let onMute {
                        Button("30 gün sustur") { onMute(hit, event) }
                            .buttonStyle(.plain)
                            .font(Tokens.Typography.text(9, weight: .medium))
                            .foregroundStyle(Tokens.Palette.accent)
                            .help("Bu durumu 30 gün boyunca işaretleme")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Metrics.radius))
    }

    /// Commands keep one line and scroll sideways; prose wraps.
    private func textSection(_ title: String, _ text: String, field: String, wraps: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: title)
                Spacer()
                copyButton(field, text)
            }
            Group {
                if wraps {
                    Text(text)
                        .font(Tokens.Typography.text(11))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(text)
                            .font(Tokens.Typography.mono(10.5))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Palette.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func diffSection(_ lines: [DiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: "Diff")
                Spacer()
                copyButton("diff", lines.map { prefix(for: $0.kind) + $0.text }.joined(separator: "\n"))
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(prefix(for: line.kind) + line.text)
                        .font(Tokens.Typography.mono(10))
                        .foregroundStyle(color(for: line.kind))
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
            SectionLabel(text: "Yollar")
            ForEach(event.paths, id: \.self) { path in
                Text(ProjectName.display(path))
                    .font(Tokens.Typography.mono(9.5))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func rawSection(_ raw: String) -> some View {
        DisclosureGroup {
            Text(raw)
                .font(Tokens.Typography.mono(9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        } label: {
            SectionLabel(text: "Ham veri (maskeli)")
        }
    }

    private func copyButton(_ field: String, _ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedField = field
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copiedField == field { copiedField = nil }
            }
        } label: {
            Text(copiedField == field ? "Kopyalandı" : "Kopyala")
                .font(Tokens.Typography.text(9.5, weight: .medium))
                .foregroundStyle(Tokens.Palette.accent)
        }
        .buttonStyle(.plain)
    }

    private func prefix(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition: return "+"
        case .removal: return "-"
        case .context: return " "
        case .header: return ""
        }
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Tokens.Palette.diffAddition
        case .removal: return Tokens.Palette.diffRemoval
        case .header: return Tokens.Palette.diffHeader
        case .context: return Tokens.Palette.ink.opacity(0.78)
        }
    }
}
