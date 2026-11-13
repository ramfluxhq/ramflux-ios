// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ChatPreviews {
    public static let states: [ChatState] = { let base = [ChatState(), ChatState(loading: true), ChatState(failure: .offline), ChatState(messages: [
        MessageRecord(id: "one", sender: "Alex", kind: .text("Let us review this together."), isOwn: false),
        MessageRecord(id: "two", sender: "", kind: .text("I will take a look."), isOwn: true, receipt: "Device: delivered"),
        MessageRecord(id: "three", sender: "", kind: .deleted, isOwn: false),
    ])]
        let direct = base.map { item in var state = item; state.conversationID = "preview-thread"; state.displayTitle = "Alex"; return state }
        var group = direct[3]; group.isGroup = true; group.displayTitle = "Research"
        return direct + [group]
    }()
}
#Preview("Chat") { ChatScreen(state: ChatPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ChatPreviews.states.indices, id: \.self) { index in ChatScreen(state: ChatPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ChatPreviews.states.indices, id: \.self) { index in ChatScreen(state: ChatPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
