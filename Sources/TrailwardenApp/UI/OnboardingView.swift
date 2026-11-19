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
    @EnvironmentObject private var router: DashboardRouter
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

            NotificationPermissionRow(live: model.live)

            Button {
                Task {
                    await model.scan()
                    model.finishOnboarding()
                    // The first thing after the first scan: what the agents did.
                    router.show(.report)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Text(model.isScanning ? model.scanLabel : L(.startScan))
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

/// The first run is the only moment where asking for notification permission is
/// not an interruption: the reader is already reading what the app does.
private struct NotificationPermissionRow: View {
    @ObservedObject var live: LiveMonitor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L(.onboardingNotifications))
                .font(Tokens.Typography.text(9.5))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            switch live.permission {
            case .allowed:
                Text(L(.liveNotificationsAllowed))
                    .font(Tokens.Typography.text(9.5, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accent)
            case .unknown:
                Button(L(.liveAllowNotifications)) { live.requestNotifications() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .denied:
                Button(L(.liveOpenNotificationSettings)) {
                    if let url =
                        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
