// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum PermissionRecord: Identifiable, Equatable, Sendable {
    case grant(PermissionGrant), approval(PermissionApproval), receipt(PermissionReceipt)
    public var id: String { switch self { case .grant: "grant:" + referenceID; case .approval: "approval:" + referenceID; case .receipt: "receipt:" + referenceID } }
    public var referenceID: String { switch self { case .grant(let value): value.referenceID; case .approval(let value): value.referenceID; case .receipt(let value): value.referenceID } }
    public var expiresAt: Int64 { switch self { case .grant(let value): value.state.expiresAt; case .approval(let value): value.expiresAt; case .receipt(let value): value.expiresAt } }
}
