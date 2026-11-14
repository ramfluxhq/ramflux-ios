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
        var reply = direct[0]; reply.composer = .reply(messageID: "one", preview: "Let us review this together."); reply.draft = "Reply draft"
        var edit = direct[0]; edit.composer = .edit(messageID: "two", previousDraft: ""); edit.draft = "I will take a look."
        var localDelete = direct[3]; localDelete.pendingDelete = PendingMessageDelete(messageID: "two", scope: .local)
        var everyoneDelete = direct[3]; everyoneDelete.pendingDelete = PendingMessageDelete(messageID: "two", scope: .everyone)
        var refused = direct[0]; refused.failure = .typedRefusal("edit_conflict"); refused.composer = .edit(messageID: "two", previousDraft: "Draft"); refused.draft = "Changed"
        var reacted = direct[3]
        reacted.messages[1] = MessageRecord(id: "two", sender: "", kind: .text("I will take a look."), isOwn: true, receipt: "Device: delivered", edited: true, replyTo: "one", replyPreview: "Let us review this together.", reactions: [MessageReaction(token: "👍", count: 2)])
        return direct + [group, reply, edit, localDelete, everyoneDelete, refused, reacted]
    }()
}
#Preview("Chat") { ChatScreen(state: ChatPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ChatPreviews.states.indices, id: \.self) { index in ChatScreen(state: ChatPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ChatPreviews.states.indices, id: \.self) { index in ChatScreen(state: ChatPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
