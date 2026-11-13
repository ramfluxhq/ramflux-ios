// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct NodeRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let origin: String
    public let fingerprint: String?
    public let publicKey: String?
    public let isDefault: Bool
    public let isConfirmed: Bool
    public let pinSource: String?
    public var canCreateAccount: Bool {
        enabled && isConfirmed && (!origin.hasPrefix("http:") || ["operator", "invitation", "builtin"].contains(pinSource ?? ""))
    }
    public let enabled: Bool
    public init(id: String, origin: String, fingerprint: String? = nil, publicKey: String? = nil, isDefault: Bool = false, enabled: Bool = true, isConfirmed: Bool = false, pinSource: String? = nil) {
        self.isConfirmed = isConfirmed; self.pinSource = pinSource
        self.id = id; self.origin = origin; self.fingerprint = fingerprint; self.publicKey = publicKey; self.isDefault = isDefault; self.enabled = enabled
    }
}
