// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ConversationsPreviews {
    public static let states: [ConversationsState] = [ConversationsState(), ConversationsState(loading: true), ConversationsState(failure: .offline), ConversationsState(rows: [ConversationRecord(id: "preview-thread", title: "Alex", preview: "See you tomorrow", unreadCount: 2)])].map { original in var state = original; state.accountID = "preview-account"; return state }
}
#Preview("Inbox") { ConversationsScreen(state: ConversationsPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ConversationsPreviews.states.indices, id: \.self) { index in ConversationsScreen(state: ConversationsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ConversationsPreviews.states.indices, id: \.self) { index in ConversationsScreen(state: ConversationsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
