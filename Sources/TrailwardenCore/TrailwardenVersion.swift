// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Build-level facts shared by every Trailwarden target.
///
/// `schema` is the version of the JSON output contract (`trailwarden --json`).
/// It only changes when a field is renamed or removed; additive fields do not
/// bump it.
public enum TrailwardenVersion {
    /// The version this build was compiled from. Tests compare against this, so it
    /// stays a constant; `installed` is what a running app should show.
    public static let current = "0.2.1"
    public static let schema = 1

    /// Read from the bundle, so the value cannot drift from `project.yml` the way a
    /// second hardcoded string would.
    public static var installed: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? current
    }
}
