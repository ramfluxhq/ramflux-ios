// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import SwiftUI
import AppData
import RFDesign
public enum ChatPreviews {
    public static let states: [ChatState] = { let base = [ChatState(), ChatState(loading: true), ChatState(failure: .offline), ChatState(messages: [
        MessageRecord(id: "one", sender: "Alex", kind: .text("Let us review this together."), isOwn: false),
        MessageRecord(id: "two", sender: "", kind: .text("I will take a look."), isOwn: true, delivery: .delivered),
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
        reacted.messages[1] = MessageRecord(id: "two", sender: "", kind: .text("I will take a look."), isOwn: true, delivery: .delivered, edited: true, replyTo: "one", replyPreview: "Let us review this together.", reactions: [MessageReaction(token: "👍", count: 2)])
        var queued = direct[3]; queued.offline = true
        queued.outbox = [OutboxEntry(operationID: "q1", text: "I will send the notes this afternoon.", created: 1_767_258_000, state: .queued)]
        var failed = direct[3]
        failed.outbox = [OutboxEntry(operationID: "f1", text: "I have read it and will add comments later.", created: 1_767_258_000, state: .failed(.typedRefusal("peer_upgrade_required")))]
        var actions = direct[3]; actions.actionTarget = "two"
        // Direct-chat identity: changed (banner and service line), a send blocked by it, the review sheet, waiting for the
        // new identity, the encryption section of the details, and an agent contact.
        let change = IdentityChange(contact: "preview-alex", username: "alex", previousAnchor: "preview-a1", newAnchor: "preview-a2")
        var changed = direct[3]; changed.identity.name = "Alex"; changed.identity.state = .changed; changed.identity.change = change
        changed.identity.serviceLines = [ServiceLine(id: "changed:preview-a2", kind: .identityChanged, name: "Alex")]
        var blocked = changed
        blocked.outbox = [OutboxEntry(operationID: "b1", text: "Let us meet at noon.", created: 1_767_258_000, state: .failed(.identityChangePending("preview-alex")))]
        var review = changed; review.identity.sheetOpen = true
        var agent = review; agent.peerIsAgent = true
        agent.identity.change = IdentityChange(contact: "preview-scout", username: "scout", previousAnchor: "preview-s1", newAnchor: "preview-s2", aiFlag: true)
        var waiting = direct[3]; waiting.identity.name = "Alex"; waiting.identity.state = .changed
        var encryption = direct[3]; encryption.identity.name = "Alex"; encryption.identity.state = .tofu
        encryption.identity.security = ConversationSecurity(state: .ok, epoch: 3, peerDevices: 2)
        encryption.details = ChatDetailsState(loading: false, details: ChatDetails(muted: false, peerPrincipal: "preview-alex", peerName: "Alex"))
        var fork = direct[3]; fork.identity.name = "Alex"; fork.identity.state = .verified
        fork.identity.serviceLines = [ServiceLine(id: "fork:4", kind: .forkRecovered, name: "Alex"), ServiceLine(id: "accepted:preview-a2", kind: .identityAccepted, name: "Alex")]
        return direct + [group, reply, edit, localDelete, everyoneDelete, refused, reacted, mixedDirection, queued, failed, actions, media, changed, blocked, review, agent, waiting, encryption, fork]
    }()

    /// Media states: a photo to download with its size, one downloading, a stranger's hidden
    /// photo, an expired and a removed photo, and a file (MOB-B13 to MOB-B15 are not designed yet).
    public static let media: ChatState = {
        func photo(_ id: String, own: Bool = false, ratio: (Int, Int)? = nil, name: String = "IMG_20260101_101500.jpg", mime: String = "image/jpeg") -> MessageRecord {
            let thumbnail = ratio.map { AttachmentThumbnail(mime: "image/png", width: $0.0, height: $0.1, data: Data()) }
            return MessageRecord(id: id, sender: "Alex", kind: .text(""), isOwn: own, timestamp: 1_767_258_000, attachments: [AttachmentRecord(id: id + "#0", name: name, mime: mime, messageID: id, index: 0, size: 2_400_000, thumbnail: thumbnail)])
        }
        var state = ChatState(messages: [photo("p6", name: "Quarterly report.pdf", mime: "application/pdf"), photo("p5", own: true), photo("p4"), photo("p3", ratio: (3, 4)), photo("p2", ratio: (16, 9)), photo("p1")])
        state.conversationID = "preview-media"; state.displayTitle = "Alex"
        state.media = ["p1#0": .idle, "p2#0": .downloading, "p3#0": .blockedByPolicy, "p4#0": .expired, "p5#0": .removed, "p6#0": .idle]
        state.outbox = [OutboxEntry(operationID: "s", text: "", created: 1_767_258_000, state: .failed(.typedRefusal("recipient_limit")), media: [MediaUpload(file: URL(fileURLWithPath: "/dev/null"), fileName: "IMG_20260101_101600.jpg", mime: "image/jpeg")])]
        return state
    }()

    /// Mixed-direction fixture: Arabic and English messages on both sides, a mention, a link, a
    /// reply excerpt, a spoofed file name, two calendar days and the unread divider.
    public static let mixedDirection: ChatState = {
        let day: Int64 = 1_767_258_000
        var state = ChatState(messages: [
            MessageRecord(id: "m6", sender: "مريم", kind: .text("@Alex تمام، سأرسل الملف https://example.org/r قبل الساعة 5."), isOwn: false, timestamp: day + 86_400 + 900, replyTo: "m5", replyPreview: "Can you send the report?"),
            MessageRecord(id: "m5", sender: "", kind: .text("Can you send the report?"), isOwn: true, timestamp: day + 86_400 + 600, delivery: .delivered),
            MessageRecord(id: "m4", sender: "مريم", kind: .text("ملف"), isOwn: false, timestamp: day + 3_000, attachments: [AttachmentRecord(id: "f1", name: "invoice\u{202E}fdp.exe")]),
            MessageRecord(id: "m3", sender: "", kind: .text("مرحبا! هذه رسالة عربية في واجهة إنجليزية، وهي طويلة بما يكفي لتلتف على سطرين."), isOwn: true, timestamp: day + 2_400, delivery: .delivered),
            MessageRecord(id: "m2", sender: "Alex", kind: .text("Hello Maryam, this English message keeps its own direction."), isOwn: false, timestamp: day + 1_800),
            MessageRecord(id: "m1", sender: "", kind: .text("12:30 👍"), isOwn: true, timestamp: day + 1_200),
        ])
        state.conversationID = "preview-mixed"
        state.displayTitle = "مريم Maryam"
        state.isGroup = true
        state.unreadAnchorID = "m6"
        return state
    }()
}
#Preview("Chat") { ChatScreen(state: ChatPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ChatPreviews.states.indices, id: \.self) { index in ChatScreen(state: ChatPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ChatPreviews.states.indices, id: \.self) { index in ChatScreen(state: ChatPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
