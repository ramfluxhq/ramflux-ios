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
            guard let account else { return }; let seconds = state.retentionSeconds
            mutate { [repository] in Self.completion(await repository.retention(account: account, seconds: seconds, operationID: UUID().uuidString)) }
        case .manualRequests:
            guard let account else { return }
            mutate { [repository] in Self.completion(await repository.requireManualRequests(account: account, operationID: UUID().uuidString)) }
        case .requestRevoke(let id):
            guard !state.busy, !state.unknownMutation, let device = state.snapshot.devices.first(where: { $0.id == id && !$0.isLocal }) else { return }; state.pendingRevoke = device
        case .confirmRevoke(let id):
            guard let account, let device = state.pendingRevoke, device.id == id else { return }
            mutate { [repository] in Self.completion(await repository.revoke(account: account, device: device, operationID: UUID().uuidString)) }
        case .cancelRevoke: if !state.busy { state.pendingRevoke = nil }
        case .lock:
            guard let account else { return }
            mutate { [repository] in switch await repository.lock(account: account) { case .success: .locked; case .failure(let failure): .failure(failure) } }
        case .setDefault(let id):
            guard let node = state.snapshot.nodes.first(where: { $0.id == id }) else { return }
            mutate { [nodes] in Self.completion(await nodes.setDefault(node, operationID: UUID().uuidString)) }
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .createBackup: if canBackup { state.backupIntent = .create; state.restoreHeld = false }
        case .selectImport: if canBackup { state.importSelecting = true }
        case .importSelected(let source): state.importSelecting = false; if canBackup { state.backupIntent = .verify(source); state.restoreHeld = false }
        case .cancelImport: state.importSelecting = false
        case .requestInstall(let id):
            guard canBackup, let job = state.jobs.first(where: { $0.id == id && $0.kind == "restore" && $0.state == "verified" && $0.accountID != nil }) else { return }
            state.backupIntent = .install(job); state.restoreHeld = false
        case .restoreHold(let id, let sequence):
            if !state.busy, case .install(let job) = state.backupIntent, job.id == id, job.sequence == sequence { state.restoreHeld = true }
        case .dismissModal: if !state.busy { state.pendingRevoke = nil; state.backupIntent = nil; state.shareURL = nil; state.restoreHeld = false }
        case .submitBackup(let credentials):
            guard let account, let intent = state.backupIntent, canBackup else { credentials.erase(); return }
            if case .install = intent, !state.restoreHeld { credentials.erase(); return }
            mutate { [backup] in
                let result: RepositoryResult<BackupRecord>
                switch intent {
                case .create: result = await backup.create(account: account, credentials: credentials, operationID: UUID().uuidString)
                case .verify(let source): result = await backup.verify(account: account, source: source, credentials: credentials, operationID: UUID().uuidString)
                case .install(let job): result = await backup.install(account: account, expected: job, credentials: credentials, operationID: UUID().uuidString)
                }
                switch result { case .success: return .updated; case .failure(let failure): return .failure(failure) }
            }
        case .cancelBackupForm: if !state.busy { state.backupIntent = nil; state.restoreHeld = false }
        case .cancelJob(let id):
            guard let account, state.jobs.contains(where: { $0.id == id }) else { return }
            mutate { [backup] in Self.completion(await backup.cancel(account: account, jobID: id, operationID: UUID().uuidString)) }
        case .share(let id): state.shareURL = state.jobs.first(where: { $0.id == id && $0.kind == "backup" && $0.state == "done" })?.shareURL
        case .closeShare: state.shareURL = nil
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            let unknown = state.unknownMutation || state.busy, route = state.route, appearance = state.appearance
            state = SettingsState(route: route); state.appearance = appearance; state.unknownMutation = unknown
        }
    }
    private var canBackup: Bool { account != nil && state.attended && !state.busy && !state.unknownMutation }
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
        let showJobs = state.route == .backup
        read = Task { [weak self, repository, backup, preferences, account] in
            let snapshot = await repository.snapshot(account: account)
            let jobs: RepositoryResult<[BackupRecord]>? = if showJobs, let account { await backup.jobs(account: account) } else { nil }
            let appearance = await preferences.appearance()
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false; self.state.appearance = appearance
            switch snapshot { case .success(let value): self.state.snapshot = value; self.state.retentionSeconds = value.retentionSeconds ?? self.state.retentionSeconds
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.snapshot = SettingsSnapshot() } }
            if let jobs { switch jobs { case .success(let rows): self.state.jobs = rows; case .failure(let failure): self.state.failure = failure } }
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
