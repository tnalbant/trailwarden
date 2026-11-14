// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Turgay Nalbant

import Foundation

/// Build-level facts shared by every Trailwarden target.
///
/// `schema` is the version of the JSON output contract (`trailwarden --json`).
/// It only changes when a field is renamed or removed; additive fields do not
/// bump it.
public enum TrailwardenVersion {
    public static let current = "0.1.0-dev"
    public static let schema = 1
}
