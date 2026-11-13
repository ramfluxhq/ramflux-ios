// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct FrozenSend: Equatable, Sendable, CustomStringConvertible {
    public let operationID: String
    public let text: String
    public var description: String { "FrozenSend" }
    public init(operationID: String, text: String) { self.operationID = operationID; self.text = text }
}
public struct ChatState: Equatable, Sendable {
    public var messages: [MessageRecord] = []
    public var draft = ""
    public var loading = false
    public var sending = false
    public var failure: AppFailure?
    public var pendingSend: FrozenSend?
    public var pendingDelete: String?
    public var lastSubmission: SendOutcome?
    public init(messages: [MessageRecord] = [], loading: Bool = false, failure: AppFailure? = nil) { self.messages = messages; self.loading = loading; self.failure = failure }
}
public enum ChatAction: Equatable, Sendable, CustomStringConvertible {
    case appeared, disappeared, conceal, refresh, unavailableAttachment, draftChanged(String), send, retrySameSend, requestDelete(String), cancelDelete, confirmDelete, unavailableRevision
    public var description: String { "ChatAction" }
}
public enum ChatEvent: Equatable, Sendable { case messageSubmitted(String) }
