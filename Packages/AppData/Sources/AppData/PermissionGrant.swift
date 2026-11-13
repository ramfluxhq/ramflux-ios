// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PermissionGrant: Equatable, Sendable {
    public let referenceID: String
    public let state: PermissionGrantState
    public let argumentsHash: String?
    public init(referenceID: String, state: PermissionGrantState, argumentsHash: String? = nil) { self.referenceID = referenceID; self.state = state; self.argumentsHash = argumentsHash }
}
