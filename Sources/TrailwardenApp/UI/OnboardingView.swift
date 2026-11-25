// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import AppKit
import SwiftUI
import TrailwardenCore

/// First run: show what is read, say plainly that nothing leaves the machine,
/// then index.
struct OnboardingView: View {
    @AppStorage(LocalizationStore.defaultsKey) private var language = AppLanguage.system.rawValue
    @ObservedObject var model: AppModel
    @ObservedObject var loginItem: LoginItem
    @State private var opensAtLogin = true
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var router: DashboardRouter
    @State private var roots: [TranscriptRoot] = AppModel.transcriptRoots()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(.onboardingTitle))
                .font(Tokens.Typography.font(.subtitle, weight: .semibold))

            ForEach(roots) { root in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(root.agent.displayName)
                            .font(Tokens.Typography.font(.codeSmall))
                        Spacer()
                        Text(root.exists ? Lf(.filesCount, [root.files]) : L(.missingFolder))
                            .font(Tokens.Typography.font(.caption))
                            .foregroundStyle(Tokens.Palette.secondary)
                    }
                    Text(shortPath(root.path))
                        .font(Tokens.Typography.font(.codeSmall))
                        .foregroundStyle(Tokens.Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(L(.onboardingPrivacy))
                .font(Tokens.Typography.font(.callout))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $opensAtLogin) {
                Text(L(.loginItemTitle))
                    .font(Tokens.Typography.font(.caption))
                    .foregroundStyle(Tokens.Palette.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            NotificationPermissionRow(live: model.live)

            Button {
                Task {
                    loginItem.setEnabled(opensAtLogin)
                    await model.scan()
                    model.finishOnboarding()
                    // The first thing after the first scan: what the agents did.
                    router.show(.report)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Text(model.isScanning ? model.scanLabel : L(.startScan))
                    .font(Tokens.Typography.font(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Tokens.Palette.accentText)
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
                .font(Tokens.Typography.font(.caption))
                .foregroundStyle(Tokens.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            switch live.permission {
            case .allowed:
                Text(L(.liveNotificationsAllowed))
                    .font(Tokens.Typography.font(.caption, weight: .medium))
                    .foregroundStyle(Tokens.Palette.accentText)
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
