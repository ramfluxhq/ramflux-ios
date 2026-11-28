// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public struct NodeRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let origin: String
    public let fingerprint: String?
    public let publicKey: String?
    public let isDefault: Bool
    public let isConfirmed: Bool
    public let pinSource: String?
    /// The SDK's `safety_warnings` for this node (`tofu_unverified`, `key_changed`).
    public let safetyWarnings: [String]
    /// The node was pinned before with another key: the SDK refuses a trust-on-first-use repin and only an operator key can replace it.
    public var keyChanged: Bool { safetyWarnings.contains("key_changed") }
    public var canCreateAccount: Bool {
        guard enabled, isConfirmed, let scheme = URLComponents(string: origin)?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return scheme != "http" || ["operator", "invitation", "builtin"].contains(pinSource ?? "")
    }
    public let enabled: Bool
    public init(id: String, origin: String, fingerprint: String? = nil, publicKey: String? = nil, isDefault: Bool = false, enabled: Bool = true, isConfirmed: Bool = false, pinSource: String? = nil, safetyWarnings: [String] = []) {
        self.isConfirmed = isConfirmed; self.pinSource = pinSource; self.safetyWarnings = safetyWarnings
        self.id = id; self.origin = origin; self.fingerprint = fingerprint; self.publicKey = publicKey; self.isDefault = isDefault; self.enabled = enabled
    }
}
