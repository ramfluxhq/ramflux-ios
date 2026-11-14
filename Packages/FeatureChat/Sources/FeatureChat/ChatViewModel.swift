// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class ChatViewModel {
    public private(set) var state: ChatState
    public let conversation: String
    private let account: String
    private let repository: any ChatRepository
    private let emit: (ChatEvent) -> Void
    @ObservationIgnored private var load: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    public init(repository: any ChatRepository, account: String, conversation: String, isGroup: Bool = false, title: String? = nil, state: ChatState = ChatState(), emit: @escaping (ChatEvent) -> Void) { self.repository = repository; self.account = account; self.conversation = conversation; var initial = state; initial.conversationID = conversation; initial.isGroup = isGroup; initial.displayTitle = title ?? conversation; self.state = initial; self.emit = emit }
    public func send(_ action: ChatAction) {
        switch action {
        case .callRequested: if state.isGroup { state.failure = repository.unavailable(.calls) } else { emit(.navigate(.calls(conversation))) }
        case .detailsRequested: state.failure = repository.unavailable(.details)
        case .appeared: refresh(); observe()
        case .refresh: refresh(); observe()
        case .draftChanged(let text): if text.utf8.count <= 65_536 { state.draft = text }
        case .send: submitComposer()
        case .retrySameSend: retryHeld()
        case .beginReply(let id): beginReply(id)
        case .beginEdit(let id): beginEdit(id)
        case .cancelComposer: cancelComposer()
        case .beginReact(let id):
            guard visible(id) else { return }
            state.reactionTarget = id; state.reactionRemove = false
        case .reactionMode(let remove): state.reactionRemove = remove
        case .chooseReaction(let token): react(token, remove: false)
        case .removeReaction(let token): react(token, remove: true)
        case .cancelReaction: state.reactionTarget = nil; state.reactionRemove = false
        case .requestDelete(let id, let scope):
            guard let message = state.messages.first(where: { $0.id == id }), visible(id), scope == .local || message.isOwn == true else { return }
            state.pendingDelete = PendingMessageDelete(messageID: id, scope: scope)
        case .cancelDelete: state.pendingDelete = nil
        case .confirmDelete: confirmDelete()
        case .unavailableAttachment: state.failure = repository.unavailable(.attachmentTransfer)
        case .disappeared, .conceal:
            epoch &+= 1; readID &+= 1; watchID &+= 1; load?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            if state.sending, state.pendingSend != nil { state.failure = .outcomeUnknown }
            state.sending = false; state.loading = false; state.messages = []; state.pendingDelete = nil
            state.composer = nil; state.reactionTarget = nil; state.reactionRemove = false; state.held = nil
            if action == .conceal { state.draft = "" }
        }
    }
    private func visible(_ id: String) -> Bool {
        state.messages.contains { $0.id == id && $0.kind != .deleted && $0.kind != .callHistory }
    }
    private func busy() -> Bool { state.loading || state.sending || state.pendingSend != nil || state.held != nil }
    private func beginReply(_ id: String) {
        guard !busy(), let message = state.messages.first(where: { $0.id == id }), visible(id) else { return }
        let preview = switch message.kind { case .text(let text): text; default: "" }
        state.composer = .reply(messageID: id, preview: preview); state.reactionTarget = nil
    }
    private func beginEdit(_ id: String) {
        guard !busy(), let message = state.messages.first(where: { $0.id == id }), message.isOwn == true, case .text(let text) = message.kind else { return }
        state.composer = .edit(messageID: id, previousDraft: state.draft); state.draft = text; state.reactionTarget = nil
    }
    private func cancelComposer() {
        guard state.held == nil else { return }
        if case .edit(_, let previous) = state.composer { state.draft = previous }
        state.composer = nil
    }
    private func submitComposer() {
        guard !state.loading, !state.sending, state.pendingSend == nil, state.held == nil else { return }
        guard !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch state.composer {
        case .edit(let messageID, _):
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft)
            state.held = .revision(operationID: attempt.operationID, messageID: messageID, text: attempt.text, reply: false)
            runHeld { [repository, account, conversation] in await repository.edit(account: account, conversation: conversation, message: messageID, text: attempt.text, operationID: attempt.operationID) }
        case .reply(let messageID, _):
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft)
            state.held = .revision(operationID: attempt.operationID, messageID: messageID, text: attempt.text, reply: true)
            runHeld { [repository, account, conversation] in await repository.reply(account: account, conversation: conversation, message: messageID, text: attempt.text, operationID: attempt.operationID) }
        case nil:
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft); state.pendingSend = attempt; submit(attempt)
        }
    }
    private func retryHeld() {
        guard !state.sending else { return }
        if let attempt = state.pendingSend { submit(attempt); return }
        guard let held = state.held else { return }
        switch held {
        case .revision(let operationID, let messageID, let text, let reply):
            runHeld { [repository, account, conversation] in
                reply ? await repository.reply(account: account, conversation: conversation, message: messageID, text: text, operationID: operationID)
                    : await repository.edit(account: account, conversation: conversation, message: messageID, text: text, operationID: operationID)
            }
        case .reaction(let operationID, let messageID, let token, let remove):
            runHeld { [repository, account, conversation] in await repository.react(account: account, conversation: conversation, message: messageID, token: token, remove: remove, operationID: operationID) }
        case .deletion(let operationID, let messageID, let scope):
            runHeld { [repository, account, conversation] in await repository.delete(account: account, conversation: conversation, message: messageID, scope: scope, operationID: operationID) }
        }
    }
    private func react(_ token: String, remove: Bool) {
        guard !busy(), let messageID = state.reactionTarget, ChatReactionPalette.tokens.contains(token) else { return }
        let operationID = UUID().uuidString
        state.reactionTarget = nil; state.reactionRemove = false
        state.held = .reaction(operationID: operationID, messageID: messageID, token: token, remove: remove)
        runHeld { [repository, account, conversation] in await repository.react(account: account, conversation: conversation, message: messageID, token: token, remove: remove, operationID: operationID) }
    }
    private func confirmDelete() {
        guard !busy(), let pending = state.pendingDelete else { return }
        let operationID = UUID().uuidString
        state.pendingDelete = nil
        state.held = .deletion(operationID: operationID, messageID: pending.messageID, scope: pending.scope)
        runHeld { [repository, account, conversation] in await repository.delete(account: account, conversation: conversation, message: pending.messageID, scope: pending.scope, operationID: operationID) }
    }
    private func runHeld(_ work: @escaping @Sendable () async -> RepositoryResult<Void>) {
        state.sending = true; state.failure = nil; let current = epoch; let held = state.held
        mutation = Task { [weak self] in
            let result = await work()
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.sending = false
            switch result {
            case .success:
                self.finish(held); self.refresh()
            case .failure(let error):
                self.state.failure = error
                if error != .outcomeUnknown && error != .offline { self.state.held = nil }
            }
        }
    }
    private func finish(_ held: HeldMutation?) {
        switch held {
        case .revision(_, _, let text, let reply):
            if reply {
                if state.draft == text { state.draft = "" }
                state.composer = nil
            } else if case .edit(_, let previous) = state.composer {
                state.draft = previous; state.composer = nil
            }
        default: break
        }
        state.held = nil
    }
    private func submit(_ attempt: FrozenSend) {
        state.sending = true; state.failure = nil; let current = epoch
        mutation = Task { [weak self, repository, account, conversation] in
            let result = await repository.send(account: account, conversation: conversation, text: attempt.text, operationID: attempt.operationID)
            let retained = await repository.sendState(account: account, conversation: conversation)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.sending = false
            if let retained, retained.unresolved { self.state.pendingSend = FrozenSend(operationID: retained.operationID, text: retained.text) }
            switch result {
            case .success(let outcome):
                self.state.lastSubmission = outcome
                if outcome.state == .submitted {
                    self.state.pendingSend = nil
                    if self.state.draft == attempt.text { self.state.draft = "" }
                    self.emit(.messageSubmitted(outcome.messageID)); self.refresh()
                } else { self.state.failure = .unavailableResource("FeatureChat.copy.8a7b78a5873c") }
            case .failure(let error):
                self.state.failure = error
                if error != .outcomeUnknown && error != .offline { self.state.pendingSend = nil }
            }
        }
    }
    private func refresh() {
        readID &+= 1; let current = readID; state.loading = true; load?.cancel()
        load = Task { [weak self, repository, account, conversation] in
            let result = await repository.messages(account: account, conversation: conversation)
            let retained = await repository.sendState(account: account, conversation: conversation)
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false
            if let retained {
                if retained.unresolved {
                    self.state.pendingSend = FrozenSend(operationID: retained.operationID, text: retained.text)
                    if self.state.draft.isEmpty { self.state.draft = retained.text }
                    self.state.failure = .outcomeUnknown
                } else if case .success(let outcome) = retained.result {
                    self.state.lastSubmission = outcome; self.state.pendingSend = nil
                    if outcome.state == .submitted, self.state.draft == retained.text { self.state.draft = "" }
                }
            }
            switch result { case .success(let rows): self.state.messages = rows; case .failure(let error): self.state.failure = error; if error == .locked { self.state.messages = [] } }
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let current = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await event in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch event { case .invalidated: if self.state.loading { self.pendingRefresh = true } else { self.refresh() }; case .failed(let error): self.state.failure = error }
            }
            await observation.stop()
            if let self, self.watchID == current { self.observer = nil }
        }
    }
    public func settle() async { await mutation?.value; while true { let current = readID; await load?.value; if current == readID { return } } }
    deinit { load?.cancel(); mutation?.cancel(); observer?.cancel() }
}
