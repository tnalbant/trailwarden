// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// First run: show what is read, say plainly that nothing leaves the machine,
/// then index.
struct OnboardingView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var roots: [TranscriptRoot] = AppModel.transcriptRoots()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(.onboardingTitle))
                .font(Tokens.Typography.serif(13, weight: .semibold))

            ForEach(roots) { root in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(root.agent.rawValue)
                            .font(Tokens.Typography.mono(9))
                        Spacer()
                        Text(root.exists ? Lf(.filesCount, [root.files]) : L(.missingFolder))
                            .font(Tokens.Typography.text(9))
                            .foregroundStyle(Tokens.Palette.secondary)
                    }
                    Text(shortPath(root.path))
                        .font(Tokens.Typography.mono(8.5))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(L(.onboardingPrivacy))
                .font(Tokens.Typography.text(10))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await model.scan()
                    model.finishOnboarding()
                    // The first thing after the first scan: what the agents did.
                    openWindow(id: "report")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Text(model.isScanning ? L(.scanning) : L(.startScan))
                    .font(Tokens.Typography.text(11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Tokens.Palette.accent)
                    .foregroundStyle(Tokens.Palette.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(model.isScanning)
        }
        .padding(.horizontal, Tokens.Metrics.gutter)
        .padding(.vertical, 12)
    }

    private func shortPath(_ path: String) -> String {
        Redactor().shortenHome(path)
    }
}
