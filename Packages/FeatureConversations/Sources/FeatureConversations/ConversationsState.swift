// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct ConversationsState: Equatable, Sendable {
    public var accountID: String?
    /// Display name shown under the title. Never the account id.
    public var accountTitle = ""
    /// Pending inbound contact requests; the message-requests row derives its detail from it.
    public var strangersUnread: UInt?
    public var rows: [ConversationRecord] = []
    public var loading = false
    public var loadingMore = false
    public var canLoadMore = false
    /// Rows above the window were evicted; reaching the first row reloads the top of the list.
    public var canLoadBefore = false
    public var failure: AppFailure?
    public var query = ""
    public init(rows: [ConversationRecord] = [], loading: Bool = false, failure: AppFailure? = nil) { self.rows = rows; self.loading = loading; self.failure = failure }
}
