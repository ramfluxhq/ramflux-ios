// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PermissionReceipt: Equatable, Sendable {
    public let referenceID: String
    public let decisionID: String
    public let grantID: String
    public let binding: PermissionTaskBinding
    public let status: String
    public let deliveryState: String
    public let reasonCode: String?
    public let expiresAt: Int64
    public init(referenceID: String, decisionID: String, grantID: String, binding: PermissionTaskBinding, status: String, deliveryState: String, reasonCode: String? = nil, expiresAt: Int64) { self.referenceID = referenceID; self.decisionID = decisionID; self.grantID = grantID; self.binding = binding; self.status = status; self.deliveryState = deliveryState; self.reasonCode = reasonCode; self.expiresAt = expiresAt }
}
