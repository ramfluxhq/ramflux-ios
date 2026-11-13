// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct ConversationsState: Equatable, Sendable {
    public var rows: [ConversationRecord] = []
    public var loading = false
    public var failure: AppFailure?
    public var query = ""
    public init(rows: [ConversationRecord] = [], loading: Bool = false, failure: AppFailure? = nil) { self.rows = rows; self.loading = loading; self.failure = failure }
}
