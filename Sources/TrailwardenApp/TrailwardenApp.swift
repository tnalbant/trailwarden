// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailwardenCore

@main
struct TrailwardenApp: App {
    var body: some Scene {
        WindowGroup("Trailwarden") {
            VStack(spacing: 8) {
                Text("Trailwarden").font(.largeTitle)
                Text("v\(TrailwardenVersion.current)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 420, minHeight: 260)
        }
    }
}
