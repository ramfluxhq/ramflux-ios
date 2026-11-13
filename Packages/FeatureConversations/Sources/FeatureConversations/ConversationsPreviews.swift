// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ConversationsPreviews {
    public static let states = [ConversationsState(), ConversationsState(loading: true), ConversationsState(failure: .offline), ConversationsState(rows: [ConversationRecord(id: "preview-thread", title: "Alex", preview: "See you tomorrow", unreadCount: 2)])]
}
#Preview("Inbox") { ConversationsScreen(state: ConversationsPreviews.states[3], onAction: { _ in }) }
