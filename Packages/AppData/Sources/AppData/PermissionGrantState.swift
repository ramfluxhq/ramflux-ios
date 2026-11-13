// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PermissionGrantState: Equatable, Sendable {
    public let server: String
    public let tool: String
    public let scope: String?
    public let registryHash: String
    public let manifestHash: String
    public let fullDelegation: Bool
    public let allowedCapabilities: [String]
    public let revoked: Bool
    public let expiresAt: Int64
    public init(server: String, tool: String, scope: String? = nil, registryHash: String, manifestHash: String, fullDelegation: Bool, allowedCapabilities: [String], revoked: Bool, expiresAt: Int64) { self.server = server; self.tool = tool; self.scope = scope; self.registryHash = registryHash; self.manifestHash = manifestHash; self.fullDelegation = fullDelegation; self.allowedCapabilities = allowedCapabilities; self.revoked = revoked; self.expiresAt = expiresAt }
}
