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
    public init(repository: any ChatRepository, account: String, conversation: String, state: ChatState = ChatState(), emit: @escaping (ChatEvent) -> Void) { self.repository = repository; self.account = account; self.conversation = conversation; var initial = state; initial.conversationID = conversation; self.state = initial; self.emit = emit }
    public func send(_ action: ChatAction) {
        switch action {
        case .callRequested: state.failure = repository.unavailable(.calls)
        case .detailsRequested: state.failure = repository.unavailable(.details)
        case .appeared: refresh(); observe()
        case .refresh: refresh(); observe()
        case .draftChanged(let text): if text.utf8.count <= 65_536 { state.draft = text }
        case .send:
            guard !state.loading else { return }
            guard !state.sending, state.pendingSend == nil, !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let attempt = FrozenSend(operationID: UUID().uuidString, text: state.draft); state.pendingSend = attempt; submit(attempt)
        case .retrySameSend: if !state.sending, let attempt = state.pendingSend { submit(attempt) }
        case .requestDelete(let id): if state.messages.contains(where: { $0.id == id && $0.kind != .deleted && $0.kind != .callHistory }) { state.pendingDelete = id }
        case .cancelDelete: state.pendingDelete = nil
        case .confirmDelete:
            guard !state.sending, let id = state.pendingDelete else { return }
            state.sending = true; state.pendingDelete = nil; let current = epoch
            mutation = Task { [weak self, repository, account, conversation] in
                let result = await repository.delete(account: account, conversation: conversation, message: id, operationID: UUID().uuidString)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                self.state.sending = false
                switch result { case .success: self.refresh(); case .failure(let error): self.state.failure = error }
            }
        case .unavailableRevision: state.failure = repository.unavailable(.revisions)
        case .unavailableAttachment: state.failure = repository.unavailable(.attachmentTransfer)
        case .disappeared, .conceal:
            epoch &+= 1; readID &+= 1; watchID &+= 1; load?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            if state.sending, state.pendingSend != nil { state.failure = .outcomeUnknown }
            state.sending = false; state.loading = false; state.messages = []; state.pendingDelete = nil
            if action == .conceal { state.draft = "" }
        }
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
                } else { self.state.failure = .notAvailable(FeatureChatStrings.text("copy.8a7b78a5873c")) }
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
