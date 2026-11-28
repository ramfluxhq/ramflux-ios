// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
import FeatureChat

/// The group chat on the shared `ChatScreen`: maps `MlsGroupSession` snapshots to `ChatState` and handles the actions a
/// group supports (send, retry, load older, delete, refresh, reply, mentions). Direct-chat actions that do not apply (media,
/// reactions, edit, calls) are ignored. Sends go to the session, which keeps the outcome if this model goes away.
@Observable @MainActor public final class MlsGroupChatModel {
    public private(set) var state: ChatState
    public let groupID: String
    @ObservationIgnored private let session: MlsGroupSession
    @ObservationIgnored private let openInfo: () -> Void
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var appeared = false
    @ObservationIgnored private var mentions: [String: String] = [:]   // anchor -> inserted "@Name"
    @ObservationIgnored private var replyTo: String?

    public init(session: MlsGroupSession, groupID: String, title: String, openInfo: @escaping () -> Void) {
        self.session = session; self.groupID = groupID; self.openInfo = openInfo
        var initial = ChatState(loading: true)
        initial.isGroup = true; initial.conversationID = groupID; initial.displayTitle = title; initial.mls = MlsChatState()
        state = initial
    }

    public func send(_ action: ChatAction) {
        switch action {
        case .appeared: appear()
        case .disappeared, .conceal: disappear()
        case .refresh: Task { [session, groupID] in
            await session.refresh(groupID)
            if await session.timelineSnapshot(groupID).phase != .ready { await session.loadNewest(groupID) }
        }
        case .loadOlder: Task { [session, groupID] in await session.loadOlder(groupID) }
        case .jumpToLatest: Task { [session, groupID] in await session.loadNewest(groupID) }
        case .draftChanged(let text): if text.utf8.count <= 65_536 { state.draft = text }
        case .send: submit()
        case .beginReply(let id): state.actionTarget = nil; beginReply(id)
        case .cancelComposer: state.composer = nil; replyTo = nil
        case .openActions(let id): if state.messages.contains(where: { $0.id == id }) { state.actionTarget = id }
        case .closeActions: state.actionTarget = nil
        case .selectText(let id): state.actionTarget = nil; if state.messages.contains(where: { $0.id == id }) { state.textSelectionTarget = id }
        case .closeTextSelection: state.textSelectionTarget = nil
        case .detailsRequested: openInfo()
        case .mlsRetry(let id): Task { [session, groupID] in await session.retry(groupID, localID: id) }
        case .mlsDiscard(let id): Task { [session, groupID] in await session.discard(groupID, localID: id) }
        case .mlsRequestDelete(let id): state.actionTarget = nil; state.mls?.deleteTarget = id
        case .mlsCancelDelete: state.mls?.deleteTarget = nil
        case .mlsConfirmDelete:
            guard let id = state.mls?.deleteTarget else { return }
            state.mls?.deleteTarget = nil
            Task { [session, groupID] in await session.deletePost(groupID, postID: id) }
        case .mlsMentionPicker(let open): state.mls?.mentionPicker = open
        case .mlsMention(let anchor): mention(anchor)
        case .mlsDismissError: Task { [session, groupID] in await session.clearActionError(groupID) }
        default: break
        }
    }

    private func appear() {
        guard !appeared else { return }
        appeared = true
        observer = Task { [weak self] in
            guard let session = self?.session, let group = self?.groupID else { return }
            let changes = await session.changes()
            await self?.reload()
            await session.open(group)
            await self?.reload()
            for await _ in changes {
                await self?.reload()
                await session.markRead(group)
            }
        }
    }
    private func disappear() {
        appeared = false
        observer?.cancel(); observer = nil
        Task { [session, groupID] in await session.close(groupID) }
    }

    private func reload() async {
        let snapshot = await session.timelineSnapshot(groupID)
        let candidates = await session.mentionCandidates(groupID)
        let named = await session.group(groupID)?.name
        var mls = state.mls ?? MlsChatState()
        mls.entries = snapshot.entries; mls.readOnly = snapshot.readOnly; mls.composerOffUntil = snapshot.composerOffUntil
        mls.mentionCandidates = candidates
        if case .failed(let error) = snapshot.phase { mls.actionError = snapshot.actionError ?? error } else { mls.actionError = snapshot.actionError }
        var next = state
        next.mls = mls
        next.messages = mls.messageRecords()
        next.loading = snapshot.phase == .loading
        next.olderAvailable = snapshot.olderAvailable; next.loadingOlder = snapshot.loadingOlder; next.detached = snapshot.detached
        if let named, !named.isEmpty { next.displayTitle = named }
        if next != state { state = next }
    }

    private func beginReply(_ id: String) {
        guard state.mls?.readOnly == nil, let record = state.messages.first(where: { $0.id == id }) else { return }
        replyTo = id
        var preview = ""
        if case .text(let text) = record.kind { preview = String(text.prefix(120)) }
        state.composer = .reply(messageID: id, preview: preview)
    }
    private func mention(_ anchor: String) {
        state.mls?.mentionPicker = false
        guard let member = state.mls?.mentionCandidates.first(where: { $0.anchor == anchor }) else { return }
        let name = MlsChatText.displayName(MlsAuthor(anchor: member.anchor, display: member.display), locale: .current)
        let token = "@" + name
        mentions[anchor] = token
        state.draft += (state.draft.isEmpty || state.draft.hasSuffix(" ") ? "" : " ") + token + " "
    }
    private func submit() {
        guard state.mls?.readOnly == nil, state.mls?.composerOffUntil == nil else { return }
        let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Only the mentions whose token is still in the text are sent (anchors of the loaded members).
        let anchors = mentions.filter { text.contains($0.value) }.map(\.key).sorted()
        let reply = replyTo
        state.draft = ""; state.composer = nil; replyTo = nil; mentions = [:]
        Task { [session, groupID] in await session.send(groupID, text: text, replyTo: reply, mentions: anchors) }
    }
}
