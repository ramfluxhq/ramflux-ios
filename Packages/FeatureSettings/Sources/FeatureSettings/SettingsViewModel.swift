// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class SettingsViewModel {
    public private(set) var state: SettingsState
    private let account: String?
    private let repository: any SettingsRepository
    private let backup: any BackupRepository
    private let nodes: any NodeRepository
    private let preferences: any PreferencesRepository
    private let emit: (SettingsEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    public init(repository: any SettingsRepository, backup: any BackupRepository, nodes: any NodeRepository, preferences: any PreferencesRepository,
                account: String?, state: SettingsState = SettingsState(), emit: @escaping (SettingsEvent) -> Void) {
        self.repository = repository; self.backup = backup; self.nodes = nodes; self.preferences = preferences; self.account = account; self.state = state; self.emit = emit
    }
    public func send(_ action: SettingsAction) {
        switch action {
        case .appeared, .refresh: refresh(); observe()
        case .open(let route): emit(.navigate(route))
        case .appearance(let mode):
            guard !state.busy else { return }
            mutate { [preferences] in
                switch await preferences.setAppearance(mode) { case .success: .appearance(mode); case .failure(let failure): .failure(failure) }
            }
        case .retention(let seconds): state.retentionSeconds = seconds
        case .saveRetention:
            guard account != nil else { return }; let seconds = state.retentionSeconds
            dispatch(PendingSettingsMutation(change: .retention(seconds), operationID: UUID().uuidString))
        case .manualRequests:
            guard account != nil else { return }
            dispatch(PendingSettingsMutation(change: .manualRequests, operationID: UUID().uuidString))
        case .requestRevoke(let id):
            guard !state.busy, !state.unknownMutation, let device = state.snapshot.devices.first(where: { $0.id == id && !$0.isLocal }) else { return }; state.pendingRevoke = device
        case .confirmRevoke(let id):
            guard account != nil, let device = state.pendingRevoke, device.id == id else { return }
            dispatch(PendingSettingsMutation(change: .revoke(device), operationID: UUID().uuidString))
        case .cancelRevoke: if !state.busy { state.pendingRevoke = nil }
        case .lock:
            guard account != nil else { return }
            dispatch(PendingSettingsMutation(change: .lock, operationID: UUID().uuidString))
        case .setDefault(let id):
            guard let node = state.snapshot.nodes.first(where: { $0.id == id }) else { return }
            dispatch(PendingSettingsMutation(change: .setDefault(node), operationID: UUID().uuidString))
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .createBackup, .selectImport, .importSelected, .requestInstall, .requestRestore, .cancelJob, .share:
            state.failure = repository.unavailable(.mobileBackup)
        case .submitBackup(let credentials): credentials.erase(); state.failure = repository.unavailable(.mobileBackup)
        case .cancelImport: state.importSelecting = false
        case .dismissModal, .cancelBackupForm: state.pendingRevoke = nil; state.backupIntent = nil; state.restoreHeld = false
        case .closeShare: state.shareURL = nil
        case .reconcileOriginal(let id):
            if let pending = state.pendingMutation, pending.operationID == id, !state.busy { dispatch(pending, reconciling: true) }
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            let unknown = state.unknownMutation || state.busy, route = state.route, appearance = state.appearance
            state = SettingsState(route: route); state.appearance = appearance; state.unknownMutation = unknown
        }
    }
    private func dispatch(_ attempt: PendingSettingsMutation, reconciling: Bool = false) {
        guard !state.busy, reconciling || !state.unknownMutation else { return }
        readID &+= 1; read?.cancel(); state.loading = false; state.busy = true; let current = epoch
        mutation = Task { [weak self, repository, account] in
            let result = await repository.mutate(account: account, change: attempt.change, operationID: attempt.operationID)
            let pending = await repository.pending(account: account)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pendingMutation = pending; self.state.unknownMutation = pending != nil
            switch result {
            case .success: self.state.pendingRevoke = nil; if attempt.change == .lock { self.emit(.locked) } else { self.refresh() }
            case .failure(let failure): self.state.failure = failure; self.state.unknownMutation = pending != nil || failure == .outcomeUnknown || failure == .offline
            }
        }
    }
    private enum Completion: Sendable { case updated, locked, appearance(AppearanceMode), failure(AppFailure) }
    private nonisolated static func completion(_ result: RepositoryResult<Void>) -> Completion { switch result { case .success: .updated; case .failure(let failure): .failure(failure) } }
    private func mutate(_ operation: @escaping @Sendable () async -> Completion) {
        guard !state.busy, !state.unknownMutation else { return }
        let current = epoch; state.busy = true; state.failure = nil
        mutation = Task { [weak self] in
            let result = await operation()
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false
            switch result {
            case .updated: self.state.pendingRevoke = nil; self.state.backupIntent = nil; self.state.restoreHeld = false; self.refresh()
            case .locked: self.state.snapshot = SettingsSnapshot(); self.emit(.locked)
            case .appearance(let mode): self.state.appearance = mode; self.emit(.appearanceChanged(mode))
            case .failure(let failure): self.state.failure = failure; self.state.unknownMutation = failure == .outcomeUnknown
            }
        }
    }
    private func refresh() {
        readID &+= 1; let current = readID; state.loading = true; read?.cancel()
        read = Task { [weak self, repository, preferences, account] in
            let snapshot = await repository.snapshot(account: account)
            let pending = await repository.pending(account: account)
            let appearance = await preferences.appearance()
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false; self.state.appearance = appearance; self.state.pendingMutation = pending; self.state.unknownMutation = pending != nil
            switch snapshot { case .success(let value): self.state.snapshot = value; self.state.retentionSeconds = value.retentionSeconds ?? self.state.retentionSeconds
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.snapshot = SettingsSnapshot() } }

            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func observe() {
        guard observer == nil, let account else { return }; watchID &+= 1; let current = watchID
        observer = Task { [weak self, repository] in
            let observation = await repository.observe(account: account)
            for await event in observation.stream {
                guard !Task.isCancelled, let self else { break }
                switch event { case .invalidated: self.state.attended = true; if self.state.loading { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.state.attended = false; self.state.failure = failure }
            }
            await observation.stop(); if let self, self.watchID == current { self.observer = nil; self.state.attended = false }
        }
    }
    public func settle() async { await mutation?.value; await read?.value }
    deinit { read?.cancel(); mutation?.cancel(); observer?.cancel() }
}
