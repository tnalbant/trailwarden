// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

/// Placeholder panel for the timeline that D8 fills in: it proves the window,
/// the tokens and the data path work, and gives the menu bar a target.
struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trailwarden")
                    .font(Tokens.Typography.serif(20, weight: .semibold))
                Spacer()
                Text("\(model.snapshot.totalEvents) olay · \(model.snapshot.sessions.count) oturum")
                    .font(Tokens.Typography.mono(10))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Zaman çizelgesi")
                Text("Olay akışı yakında burada.")
                    .font(Tokens.Typography.serif(15))
                Text("Şimdilik özet: bugün \(model.snapshot.criticalToday) kritik, \(model.snapshot.warnToday) uyarı.")
                    .font(Tokens.Typography.text(12))
                    .foregroundStyle(Tokens.Palette.secondary)
                Button {
                    Task { await model.scan() }
                } label: {
                    Text(model.isScanning ? "Taranıyor…" : "Yeniden tara")
                        .font(Tokens.Typography.text(11, weight: .medium))
                }
                .disabled(model.isScanning)
            }
            .padding(20)

            Spacer()
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(Tokens.Palette.paper)
        .foregroundStyle(Tokens.Palette.ink)
    }
}
