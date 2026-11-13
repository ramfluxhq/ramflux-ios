// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct GroupRequestRecord: Equatable, Sendable, Identifiable {
    public let id: String
    public let groupID: String
    public let status: String
    public let waitingForOwner: Bool
    public let expiresAt: Int64
    public init(id: String, groupID: String, status: String, waitingForOwner: Bool, expiresAt: Int64) { self.id = id; self.groupID = groupID; self.status = status; self.waitingForOwner = waitingForOwner; self.expiresAt = expiresAt }
}
