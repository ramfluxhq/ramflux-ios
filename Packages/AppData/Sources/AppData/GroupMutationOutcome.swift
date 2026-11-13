// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct GroupMutationOutcome: Equatable, Sendable {
    public let groupID: String
    public let waitingForOwner: Bool
    public let expired: Bool
    public let requestID: String?
    public init(groupID: String, waitingForOwner: Bool, requestID: String? = nil, expired: Bool = false) { self.groupID = groupID; self.waitingForOwner = waitingForOwner; self.requestID = requestID; self.expired = expired }
}
