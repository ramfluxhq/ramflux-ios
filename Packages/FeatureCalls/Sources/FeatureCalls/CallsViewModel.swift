// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class CallsViewModel {
    public private(set) var state: CallsState
    private let repository: any CallsRepository
    private let microphone: any MicrophoneRepository
    private let account: String
    private let emit: (CallsEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    public init(repository: any CallsRepository, microphone: any MicrophoneRepository, account: String, state: CallsState = CallsState(), emit: @escaping (CallsEvent) -> Void) { self.repository = repository; self.microphone = microphone; self.account = account; var initial = state; initial.accountID = account; initial.audioFailure = repository.audioUnavailable(); self.state = initial; self.emit = emit }
    public func send(_ action: CallsAction) {
        switch action {
        case .appeared, .refresh: refresh(); observe()
        case .filter(let value): state.query = String(value.prefix(256)); project()
        case .mode(let mode):
            guard !state.busy else { return }
            if case .detail(let id) = mode, !state.calls.contains(where: { $0.id == id }) { return }
            state.mode = mode; state.failure = nil; project(); refresh()
        case .start:
            guard !state.busy, state.pending == nil, case .dial(let conversation) = state.mode else { return }
            perform { [repository, account] in await repository.start(account: account, conversation: conversation) }
        case .answer:
            guard !state.busy, state.pending == nil, let selected = state.selected, selected.canDecline else { return }
            perform { [repository, account] in await repository.answer(account: account, expected: selected) }
        case .audioControl: state.failure = repository.audioUnavailable()
        case .signal(let signal, let callID, let sequence):
            guard state.pending == nil, !state.busy, let selected = state.selected, state.fresh, selected.id == callID, selected.sequence == sequence,
                  (signal == .decline ? selected.canDecline : selected.canHangup) else { return }
            let attempt = CallSignalAttempt(expected: selected, signal: signal, operationID: UUID().uuidString)
            perform { [repository, account] in await repository.signal(account: account, attempt: attempt) }
        case .reconcile(let operationID):
            guard !state.busy, let pending = state.pending, pending.operationID == operationID else { return }
            perform { [repository, account] in await repository.signal(account: account, attempt: pending) }
        case .openSettings: emit(.openSystemSettings)
        case .settingsResult(let opened): if !opened { state.failure = .localFailure }
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            let mode = state.mode; state = CallsState(mode: mode)
        }
    }
    private func perform(_ operation: @escaping @Sendable () async -> RepositoryResult<CallRecord>) {
        guard !state.busy else { return }
        readID &+= 1; read?.cancel(); state.loading = false; state.busy = true; let current = epoch
        mutation = Task { [weak self, repository, account] in
            let result = await operation(); let pending = await repository.pending(account: account)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pending = pending
            switch result { case .success(let row):
                self.state.mode = .detail(row.id); self.refresh()
            case .failure(let failure): self.state.failure = failure; self.state.fresh = false; if failure == .locked { self.state.calls = []; self.state.selected = nil }; if self.pendingRefresh { self.pendingRefresh = false; self.refresh() } }
        }
    }
    private func refresh() {
        guard !state.busy else { pendingRefresh = true; return }
        readID &+= 1; let id = readID; read?.cancel(); state.loading = true; state.fresh = false; state.accountID = account; state.audioFailure = repository.audioUnavailable()
        read = Task { [weak self, repository, microphone, account] in
            let pending = await repository.pending(account: account)
            let result = await repository.list(account: account), permission = await microphone.status()
            guard !Task.isCancelled, let self, self.readID == id else { return }
            self.state.pending = pending; self.state.microphone = permission; self.state.loading = false
            switch result { case .success(let rows): self.state.calls = rows; self.state.fresh = true; self.state.failure = nil
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.calls = [] } }
            self.project()
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func project() {
        state.visibleCalls = state.calls.filter { state.query.isEmpty || $0.peerID.localizedCaseInsensitiveContains(state.query) }
        if case .detail(let id) = state.mode { state.selected = state.calls.first { $0.id == id } } else { state.selected = nil }
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let id = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                self.state.fresh = false
                switch update { case .invalidated: if self.state.loading || self.state.busy { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.state.failure = failure }
            }
            await observation.stop(); if let self, self.watchID == id { self.observer = nil; self.state.fresh = false }
        }
    }
    public func settle() async { await mutation?.value; while true { let id = readID; await read?.value; if id == readID { return } } }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
