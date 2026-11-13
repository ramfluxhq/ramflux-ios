// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PermissionRecord: Identifiable, Equatable, Sendable {
    public var id: String { (approval ? "approval:" : "grant:") + referenceID }
    public let referenceID: String
    public let approval: Bool
    public let server: String
    public let tool: String
    public let capability: String
    public let status: String
    public let expiresAt: Int64
    public let scope: String?
    public let argumentsHash: String?
    public init(id: String, approval: Bool, server: String, tool: String, capability: String, status: String, expiresAt: Int64, scope: String? = nil, argumentsHash: String? = nil) { self.referenceID = id; self.approval = approval; self.server = server; self.tool = tool; self.capability = capability; self.status = status; self.expiresAt = expiresAt; self.scope = scope; self.argumentsHash = argumentsHash }
}
