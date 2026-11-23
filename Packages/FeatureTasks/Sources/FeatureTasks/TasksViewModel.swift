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
            case .list(let id): guard state.conversations.rows.contains(where: { $0.id == id }) else { return }
            case .detail(let conversation, let id): guard state.tasks.rows.contains(where: { $0.id == id && $0.conversationID == conversation }) else { return }
            case .permission(let id): guard state.permissions.rows.contains(where: { $0.id == id }) else { return }
            default: break
            }
            if case .detail = mode {} else { state.tasks = RowWindow() }
            if case .permission = mode {} else if mode != .permissions { state.permissions = RowWindow() }
            state.mode = mode; state.selected = nil; state.selectedPermission = nil; state.confirmation = nil; state.approvalConfirmation = nil; state.outcome = nil; refresh()
        case .loadMore: if !state.loading, !state.busy { loadMore() }
        case .prepareApproval(let approve):
            guard state.fresh, !state.busy, case .approval(let approval)? = state.selectedPermission, approval.status == "pending" else { return }
            if approve && approval.needsAppSignature { state.failure = .unavailableResource("tasks.approval.appSignature"); return }
            state.approvalConfirmation = ApprovalConfirmation(approval: approval, approve: approve)
        case .confirmApproval(let id):
            guard state.fresh, !state.busy, let confirmation = state.approvalConfirmation, confirmation.id == id else { return }
            decide(confirmation)
        case .prepare(let kind):
            guard state.fresh, !state.busy, state.pending == nil, let selected = state.selected, !selected.pendingResolution,
                kind == .cancel ? ["running", "needs_me", "proposed"].contains(selected.status) : selected.status == "proposed" else { return }
            state.confirmation = TaskHostConfirmation(attempt: PendingTaskMutation(arguments: TaskMutationArguments(task: selected, kind: kind), operationID: UUID().uuidString))
        case .confirm(let id):
            guard state.fresh, !state.busy, state.pending == nil, let confirmation = state.confirmation, confirmation.id == id else { return }; perform(confirmation.attempt)
        case .cancelConfirmation: if !state.busy { state.confirmation = nil; state.approvalConfirmation = nil }
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
    private func decide(_ confirmation: ApprovalConfirmation) {
        generation &+= 1; read?.cancel(); state.loading = false; state.busy = true; state.approvalConfirmation = nil; let current = epoch
        mutation = Task { [weak self, repository, account] in
            let result = await repository.decideApproval(account: account, approval: confirmation.approval, approve: confirmation.approve, operationID: UUID().uuidString)
            guard !Task.isCancelled, let self, self.epoch == current else { return }; self.state.busy = false
            switch result { case .success: self.refresh(); case .failure(let failure): self.state.failure = failure; self.state.fresh = false; if self.pendingRefresh { self.pendingRefresh = false; self.refresh() } }
        }
    }
    private func eraseRows() { state.tasks = RowWindow(); state.selected = nil; state.conversations = RowWindow(); state.permissions = RowWindow(); state.selectedPermission = nil; state.pending = nil; state.outcome = nil; state.approvalConfirmation = nil }
    private nonisolated static func conversationReader(_ conversations: any ConversationsRepository, account: String) -> RowPageReader<ConversationRecord> {
        { cursor, limit in
            switch await conversations.page(account: account, cursor: cursor, limit: limit) {
            case .success(let page): .success(RowPage(rows: page.rows, nextCursor: page.nextCursor))
            case .failure(let failure): .failure(failure)
            }
        }
    }
    private nonisolated static func taskReader(_ repository: any TasksRepository, account: String, conversation: String) -> RowPageReader<TaskRecord> {
        { cursor, _ in
            switch await repository.page(account: account, conversation: conversation, cursor: cursor) {
            case .success(let page): .success(RowPage(rows: page.rows, nextCursor: page.nextCursor == cursor ? nil : page.nextCursor))
            case .failure(let failure): .failure(failure)
            }
        }
    }
    private nonisolated static func permissionReader(_ repository: any TasksRepository, account: String) -> RowPageReader<PermissionRecord> {
        { cursor, limit in await repository.permissionsPage(account: account, cursor: cursor, limit: limit) }
    }
    private func loadMore() {
        generation &+= 1; let id = generation; read?.cancel(); state.loading = true
        let mode = state.mode, conversationWindow = state.conversations, taskWindow = state.tasks, permissionWindow = state.permissions
        read = Task { [weak self, repository, conversations, account] in
            let result: TasksReadResult
            switch mode {
            case .conversations: result = .conversations(await conversationWindow.after(Self.conversationReader(conversations, account: account)))
            case .list(let conversation): result = .tasks(await taskWindow.after(Self.taskReader(repository, account: account, conversation: conversation)))
            case .permissions: result = .permissions(await permissionWindow.after(Self.permissionReader(repository, account: account)))
            case .detail, .permission: result = .detail(.failure(.invalidInput))
            }
            guard !Task.isCancelled, let self, self.generation == id else { return }; self.state.loading = false
            switch result {
            case .conversations(.success(let window)): self.state.conversations = window
            case .tasks(.success(let window)): self.state.tasks = window
            case .permissions(.success(let window)): self.state.permissions = window
            case .detail: break
            case .conversations(.failure(let failure)), .tasks(.failure(let failure)), .permissions(.failure(let failure)): self.state.failure = failure
            }
        }
    }
    private func refresh() {
        guard !state.busy else { pendingRefresh = true; return }
        generation &+= 1; let id = generation, mode = state.mode; read?.cancel(); state.loading = true; state.fresh = false; state.confirmation = nil; state.approvalConfirmation = nil; state.accountID = account
        read = Task { [weak self, repository, conversations, account] in
            let pending = await repository.pending(account: account)
            let result: TasksReadResult
            switch mode {
            case .conversations: result = .conversations(await RowWindow.first(Self.conversationReader(conversations, account: account)))
            case .list(let conversation): result = .tasks(await RowWindow.first(Self.taskReader(repository, account: account, conversation: conversation)))
            case .detail(let conversation, let task): result = .detail(await repository.detail(account: account, conversation: conversation, task: task))
            case .permissions, .permission: result = .permissions(await RowWindow.first(Self.permissionReader(repository, account: account)))
            }
            guard !Task.isCancelled, let self, self.generation == id else { return }; self.state.pending = pending; self.state.loading = false; self.state.failure = nil
            @MainActor func fail(_ failure: AppFailure) { self.state.failure = failure; if failure == .locked { self.eraseRows() } }
            switch result {
            case .conversations(.success(let window)): self.state.conversations = window
            case .tasks(.success(let window)): self.state.tasks = window
            case .detail(.success(let row)): self.state.selected = row
            case .permissions(.success(let window)):
                self.state.permissions = window
                if case .permission(let selected) = mode { self.state.selectedPermission = window.rows.first { $0.id == selected } }
            case .conversations(.failure(let failure)): fail(failure)
            case .tasks(.failure(let failure)): fail(failure)
            case .detail(.failure(let failure)): fail(failure)
            case .permissions(.failure(let failure)): fail(failure)
            }
            self.state.fresh = self.state.failure == nil
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func observationEnded(_ failure: AppFailure) {
        generation &+= 1; read?.cancel(); pendingRefresh = false
        state.loading = false; state.fresh = false; state.confirmation = nil; state.approvalConfirmation = nil; state.failure = failure
        if failure == .locked { eraseRows() }
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let id = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }; self.state.fresh = false; self.state.confirmation = nil; self.state.approvalConfirmation = nil
                switch update { case .invalidated: if self.state.loading || self.state.busy { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.observationEnded(failure) }
            }
            await observation.stop(); if let self, self.watchID == id { self.observer = nil; self.observationEnded(self.state.failure ?? .resyncRequired) }
        }
    }
    public func settle() async { await mutation?.value; while true { let id = generation; await read?.value; if id == generation { return } } }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
