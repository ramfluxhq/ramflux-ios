// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct ChatState: Equatable, Sendable {
    public var isGroup = false
    public var displayTitle = ""
    public var conversationID = ""
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
