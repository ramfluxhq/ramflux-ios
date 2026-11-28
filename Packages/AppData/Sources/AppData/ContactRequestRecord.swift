// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct ContactRequestRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let principal: String
    public let name: String
    public let direction: String
    public let state: String
    public let preview: String?
    public let classification: PrincipalClassification
    public init(id: String, principal: String, name: String, direction: String, state: String, preview: String? = nil, classification: PrincipalClassification = .unknown) {
        self.classification = classification
        self.id = id; self.principal = principal; self.name = name; self.direction = direction; self.state = state; self.preview = preview
    }
}
public enum ContactDecision: String, Equatable, Sendable { case accept, decline, block }
/// Stranger actions the pinned SDK has no method for.
public enum ContactUnavailable: Sendable, Equatable { case reporting, batch, replyWithoutAcceptance }
/// Changes to an accepted contact, selected by its friend link.
public enum ContactChange: String, Equatable, Sendable { case remove, block, unblock }
