// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PendingGroupMutation: Equatable, Sendable {
    public let mutation: GroupMutation
    public let operationID: String
    public init(mutation: GroupMutation, operationID: String) { self.mutation = mutation; self.operationID = operationID }
}
