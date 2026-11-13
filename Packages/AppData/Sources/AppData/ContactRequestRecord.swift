// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct ContactRequestRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let principal: String
    public let name: String
    public let direction: String
    public let state: String
    public let preview: String?
    public let safetyNumber: String?
    public init(id: String, principal: String, name: String, direction: String, state: String, preview: String? = nil, safetyNumber: String? = nil) {
        self.id = id; self.principal = principal; self.name = name; self.direction = direction; self.state = state; self.preview = preview; self.safetyNumber = safetyNumber
    }
}
public struct ContactSafety: Equatable, Sendable {
    public let root: String
    public let number: String
    public let fingerprint: String
    public let verified: Bool
    public let requiresReview: Bool
    public init(root: String, number: String, fingerprint: String, verified: Bool, requiresReview: Bool) {
        self.root = root; self.number = number; self.fingerprint = fingerprint; self.verified = verified; self.requiresReview = requiresReview
    }
}
public enum ContactDecision: String, Equatable, Sendable { case accept, decline, block }
public enum ContactUnavailable: Sendable, Equatable { case reporting, batch, replyWithoutAcceptance, atomicSafetyVerification }
