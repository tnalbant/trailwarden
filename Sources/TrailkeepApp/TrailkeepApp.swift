// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import SwiftUI
import TrailkeepCore

@main
struct TrailkeepApp: App {
    var body: some Scene {
        WindowGroup("Trailkeep") {
            VStack(spacing: 8) {
                Text("Trailkeep").font(.largeTitle)
                Text("v\(TrailkeepVersion.current)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 420, minHeight: 260)
        }
    }
}
