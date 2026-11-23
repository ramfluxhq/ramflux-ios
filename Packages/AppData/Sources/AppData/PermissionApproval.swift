// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PermissionApproval: Equatable, Sendable {
    public let referenceID: String
    public let server: String
    public let tool: String
    public let capability: String
    public let status: String
    public let expiresAt: Int64
    public let scope: String?
    public let argumentsHash: String?
    /// SDK `confirmation_mode`; `remote_app` approvals need an app-signed grant this app cannot produce.
    public let confirmationMode: String?
    public var needsAppSignature: Bool { confirmationMode == nil || confirmationMode == "remote_app" }
    public init(referenceID: String, server: String, tool: String, capability: String, status: String, expiresAt: Int64, scope: String? = nil, argumentsHash: String? = nil, confirmationMode: String? = nil) { self.referenceID = referenceID; self.server = server; self.tool = tool; self.capability = capability; self.status = status; self.expiresAt = expiresAt; self.scope = scope; self.argumentsHash = argumentsHash; self.confirmationMode = confirmationMode }
}
