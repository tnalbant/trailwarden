// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 tnalbant

import CryptoKit
import Foundation

/// SHA-256 helper for stable event ids.
enum SHA256Hasher {
    static func hash(_ data: Data) -> SHA256.Digest {
        SHA256.hash(data: data)
    }
}
