// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ConversationsPreviews {
    /// Design sample for MOB-B01. Names and previews are fixture text, not catalog copy.
    public static let sampleRows: [ConversationRecord] = [
        ConversationRecord(id: "lin-yue", title: "林悦", preview: "好的，附件里的版本说明也请一起看。", unreadCount: 1, timeLabel: "10:24"),
        ConversationRecord(id: "nova", title: "Nova", preview: "协作设置已确认", timeLabel: "09:42", kind: "agent", avatarIcon: "orbit"),
        ConversationRecord(id: "general", title: "产品探索 · #general", preview: "收到，稍后一起看。", timeLabel: "10:23", kind: "channel", pinned: true, sender: "你："),
        ConversationRecord(id: "zhou-ning", title: "周宁", preview: "好的，明天继续。", timeLabel: "昨天", readReceipt: true),
        ConversationRecord(id: "notice", title: "团队公告", preview: "本周安排与文档", unreadCount: 5, timeLabel: "周二", muted: true),
    ]
    public static let states: [ConversationsState] = {
        var populated = ConversationsState(rows: sampleRows)
        populated.strangersUnread = 3
        return [ConversationsState(), ConversationsState(loading: true), ConversationsState(failure: .offline), populated].map { original in
            var state = original
            state.accountTitle = "林澈"
            return state
        }
    }()
}
#Preview("Inbox") { ConversationsScreen(state: ConversationsPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ConversationsPreviews.states.indices, id: \.self) { index in ConversationsScreen(state: ConversationsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ConversationsPreviews.states.indices, id: \.self) { index in ConversationsScreen(state: ConversationsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
