// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class TasksViewModel {
    public private(set) var state: TasksState
    private let repository: any TasksRepository
    private let conversations: any ConversationsRepository
    private let account: String
    private let emit: (TasksEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    public init(repository: any TasksRepository, conversations: any ConversationsRepository, account: String, state: TasksState = TasksState(), emit: @escaping (TasksEvent) -> Void) { self.repository = repository; self.conversations = conversations; self.account = account; var initial = state; initial.accountID = account; self.state = initial; self.emit = emit }
    public func send(_ action: TasksAction) {
        switch action {
        case .appeared, .refresh: refresh(); observe()
        case .mode(let mode):
            guard !state.busy else { return }
            switch mode {
            case .list(let id): guard state.conversations.contains(where: { $0.id == id }) else { return }
            case .detail(let conversation, let id): guard state.rows.contains(where: { $0.id == id && $0.conversationID == conversation }) else { return }
            case .permission(let id): guard state.permissions.contains(where: { $0.id == id }) else { return }
            default: break
            }
            state.mode = mode; state.rows = []; state.selected = nil; state.selectedPermission = nil; state.nextCursor = nil; state.confirmation = nil; state.outcome = nil; refresh()
        case .loadMore: if let cursor = state.nextCursor, !state.loading, !state.busy { refresh(cursor: cursor) }
        case .prepare(let kind):
            guard state.fresh, !state.busy, state.pending == nil, let selected = state.selected, !selected.pendingResolution,
                kind == .cancel ? ["running", "needs_me", "proposed"].contains(selected.status) : selected.status == "proposed" else { return }
            state.confirmation = TaskHostConfirmation(attempt: PendingTaskMutation(arguments: TaskMutationArguments(task: selected, kind: kind), operationID: UUID().uuidString))
        case .confirm(let id):
            guard state.fresh, !state.busy, state.pending == nil, let confirmation = state.confirmation, confirmation.id == id else { return }; perform(confirmation.attempt)
        case .cancelConfirmation: if !state.busy { state.confirmation = nil }
        case .reconcile(let id): if let pending = state.pending, pending.operationID == id, !state.busy { perform(pending) }
        case .unavailable: state.failure = repository.unavailable()
        case .disappeared:
            epoch &+= 1; generation &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            let mode = state.mode; state = TasksState(mode: mode)
        }
    }
    private func perform(_ attempt: PendingTaskMutation) {
        generation &+= 1; read?.cancel(); state.loading = false; state.busy = true; state.confirmation = nil; let current = epoch
        mutation = Task { [weak self, repository, account] in
            let result = await repository.mutate(account: account, attempt: attempt), pending = await repository.pending(account: account)
            guard !Task.isCancelled, let self, self.epoch == current else { return }; self.state.busy = false; self.state.pending = pending
            switch result { case .success(let outcome): self.state.outcome = outcome; self.refresh()
            case .failure(let failure): self.state.failure = failure; self.state.fresh = false; if failure == .locked { self.eraseRows() }; if self.pendingRefresh { self.pendingRefresh = false; self.refresh() } }
        }
    }
    private func eraseRows() { state.rows = []; state.selected = nil; state.conversations = []; state.permissions = []; state.selectedPermission = nil; state.pending = nil; state.outcome = nil; state.nextCursor = nil }
    private func refresh(cursor: String? = nil) {
        guard !state.busy else { pendingRefresh = true; return }
        generation &+= 1; let id = generation, mode = state.mode; read?.cancel(); state.loading = true; state.fresh = false; state.confirmation = nil; state.accountID = account
        read = Task { [weak self, repository, conversations, account] in
            let pending = await repository.pending(account: account)
            let result: TasksReadResult
            switch mode {
            case .conversations: result = .conversations(await conversations.list(account: account))
            case .list(let conversation): result = .page(await repository.page(account: account, conversation: conversation, cursor: cursor))
            case .detail(let conversation, let task): result = .detail(await repository.detail(account: account, conversation: conversation, task: task))
            case .permissions, .permission: result = .permissions(await repository.permissions(account: account))
            }
            guard !Task.isCancelled, let self, self.generation == id else { return }; self.state.pending = pending; self.state.loading = false; self.state.failure = nil
            @MainActor func fail(_ failure: AppFailure) { self.state.failure = failure; if failure == .locked { self.eraseRows() } }
            switch result {
            case .conversations(.success(let rows)): self.state.conversations = rows
            case .page(.success(let page)):
                if cursor == nil { self.state.rows = page.rows } else { for row in page.rows { if let index = self.state.rows.firstIndex(where: { $0.id == row.id }) { self.state.rows[index] = row } else { self.state.rows.append(row) } } }
                self.state.nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
            case .detail(.success(let row)): self.state.selected = row
            case .permissions(.success(let rows)):
                self.state.permissions = rows
                if case .permission(let selected) = mode { self.state.selectedPermission = rows.first { $0.id == selected } }
            case .conversations(.failure(let failure)): fail(failure)
            case .page(.failure(let failure)): fail(failure)
            case .detail(.failure(let failure)): fail(failure)
            case .permissions(.failure(let failure)): fail(failure)
            }
            self.state.fresh = self.state.failure == nil
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func observationEnded(_ failure: AppFailure) {
        generation &+= 1; read?.cancel(); pendingRefresh = false
        state.loading = false; state.fresh = false; state.confirmation = nil; state.failure = failure
        if failure == .locked { eraseRows() }
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let id = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }; self.state.fresh = false; self.state.confirmation = nil
                switch update { case .invalidated: if self.state.loading || self.state.busy { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.observationEnded(failure) }
            }
            await observation.stop(); if let self, self.watchID == id { self.observer = nil; self.observationEnded(self.state.failure ?? .resyncRequired) }
        }
    }
    public func settle() async { await mutation?.value; while true { let id = generation; await read?.value; if id == generation { return } } }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
