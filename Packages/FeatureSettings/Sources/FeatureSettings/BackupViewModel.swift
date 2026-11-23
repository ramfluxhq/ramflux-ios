// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
/// Owns the attended job subscription, the bounded job window and one job request at a time.
/// Secrets arrive as one-shot `SensitiveSubmission`s and are erased by the repository or here.
@Observable @MainActor public final class BackupViewModel {
    public private(set) var state: BackupState
    private let repository: any BackupRepository
    private let emit: (SettingsEvent) -> Void
    /// How long to wait before re-reading a running job; job changes reach an account subscription only this way.
    nonisolated static let pollInterval: Duration = .seconds(1)
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var discarded: Set<String> = []
    /// The restore job this screen asked the SDK to verify; once it reads verified, the install step opens
    /// by itself (the person chose the archive to restore it), instead of waiting for a second tap.
    @ObservationIgnored private var verifying: String?
    public init(repository: any BackupRepository, account: String?, emit: @escaping (SettingsEvent) -> Void) {
        self.repository = repository; self.emit = emit; state = BackupState(account: account)
    }
    public func send(_ action: BackupAction) {
        switch action {
        case .appeared: observe(); reload()
        case .refresh: reload()
        case .loadMore: loadMore()
        case .disappeared: stop()
        case .startCreate: guard state.account != nil, !state.busy else { return }; state.failure = nil; state.step = .createPassphrase(allowMissingAttachments: false)
        case .retryAllowingMissing: guard state.account != nil, !state.busy else { return }; state.failure = nil; state.step = .createPassphrase(allowMissingAttachments: true)
        case .submitCreate(let input):
            guard case .createPassphrase(let allow) = state.step, let account = state.account, ready(input) else { return }
            run { [repository] in await repository.create(account: account, credentials: input, allowMissingAttachments: allow, operationID: UUID().uuidString) }
        case .selectImport: guard !state.busy else { return }; state.failure = nil; state.importSelecting = true
        case .cancelImport: state.importSelecting = false
        case .importFailed: state.importSelecting = false; state.failure = .backup(.unreadable)
        case .importSelected(let url): state.importSelecting = false; state.step = .importPassphrase(url)
        case .submitVerify(let input):
            guard case .importPassphrase(let url) = state.step, ready(input) else { return }
            let account = state.account
            run({ [repository] in await repository.verify(account: account, source: url, credentials: input, operationID: UUID().uuidString) },
                then: { [weak self] job in self?.verifying = job.id })
        case .requestInstall(let id):
            guard !state.busy, let job = state.window.rows.first(where: { $0.id == id && $0.kind == "restore" && $0.state == "verified" }), let merge = job.merge else { return }
            state.failure = nil
            state.step = merge ? .confirmMerge(job) : .installCode(job)
        case .submitInstallCode(let input):
            guard case .installCode(let job) = state.step, ready(input) else { return }
            if let issue = input.accountCodeIssue { input.erase(); state.failure = .accountCode(issue); return }
            let account = state.account
            run { [repository] in await repository.install(account: account, expected: job, credentials: input, operationID: UUID().uuidString) }
        case .confirmMerge(let id):
            guard case .confirmMerge(let job) = state.step, job.id == id, !state.busy, state.attended else { return }
            let account = state.account
            run { [repository] in await repository.install(account: account, expected: job, credentials: nil, operationID: UUID().uuidString) }
        case .cancelJob(let id):
            guard !state.busy, state.attended else { return }
            let account = state.account
            state.busy = true; state.failure = nil; let current = epoch
            work = Task { [weak self, repository] in
                let result = await repository.cancel(account: account, jobID: id, operationID: UUID().uuidString)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                self.state.busy = false
                if case .failure(let failure) = result { self.state.failure = failure }
                self.reload()
            }
        case .export(let id):
            guard let job = state.window.rows.first(where: { $0.id == id && $0.shareURL != nil }) else { return }
            state.exporting = job
        case .exportFinished(let moved):
            // A completed move leaves nothing behind in private storage; a cancelled one keeps the archive.
            state.exporting = nil; if moved { reload() }
        case .discard(let id):
            guard !state.busy, let job = state.window.rows.first(where: { $0.id == id && $0.isTerminal }) else { return }
            discard(job)
        case .back: guard !state.busy else { return }; state.step = .overview
        case .finish: if case .restored(let id) = state.step { emit(.restored(id)) }
        }
    }
    /// Only one request at a time, and only once the SDK will admit it (attended subscription live).
    private func ready(_ input: SensitiveSubmission) -> Bool {
        guard !state.busy else { input.erase(); return false }
        guard state.attended else { input.erase(); state.failure = .backup(.attendanceRequired); return false }
        return true
    }
    private func run(_ operation: @escaping @Sendable () async -> RepositoryResult<BackupRecord>, then: @escaping @MainActor (BackupRecord) -> Void = { _ in }) {
        state.busy = true; state.failure = nil; let current = epoch
        work = Task { [weak self] in
            let result = await operation()
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false
            switch result {
            case .success(let job): self.state.step = .overview; self.state.window = self.state.window.patching(job); then(job); self.reload()
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    private func reader() -> RowPageReader<BackupRecord> {
        let account = state.account
        return { [repository] cursor, limit in await repository.jobsPage(account: account, cursor: cursor, limit: limit) }
    }
    private func reload() {
        readID &+= 1; let current = readID; state.loading = true; read?.cancel()
        let read = reader()
        self.read = Task { [weak self] in
            let result = await RowWindow<BackupRecord>.first(read)
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false
            switch result {
            case .success(let window): self.state.window = window; self.settle(window.rows)
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    private func loadMore() {
        guard state.window.canLoadAfter, !state.loading else { return }
        readID &+= 1; let current = readID; state.loading = true; let window = state.window, read = reader()
        self.read = Task { [weak self] in
            let result = await window.after(read)
            guard !Task.isCancelled, let self, self.readID == current else { return }
            self.state.loading = false
            switch result { case .success(let next): self.state.window = next; case .failure(let failure): self.state.failure = failure }
        }
    }
    /// Polls while a job runs, removes the private copy of every finished import, and reports a
    /// finished new-install restore.
    private func settle(_ rows: [BackupRecord]) {
        poll?.cancel(); poll = nil
        for job in rows where job.failure != nil {
            EventDiagnostics.note("backup job kind=\(job.kind) state=\(job.state) failure=\(job.failure?.code ?? "-") retryable=\(job.failure?.retryable ?? false)")
        }
        for job in rows where job.kind == "restore" && job.isTerminal && !discarded.contains(job.id) { discard(job, quietly: true) }
        if state.account == nil, case .overview = state.step, let done = rows.first(where: { $0.kind == "restore" && $0.state == "done" && $0.installedAccountID != nil }), let id = done.installedAccountID {
            state.step = .restored(id)
        }
        if let id = verifying, let job = rows.first(where: { $0.id == id }) {
            if job.kind == "restore", job.state == "verified", let merge = job.merge {
                verifying = nil
                if case .overview = state.step, !state.busy { state.step = merge ? .confirmMerge(job) : .installCode(job) }
            } else if job.isTerminal { verifying = nil }
        }
        guard rows.contains(where: \.isRunning) else { return }
        let current = epoch
        poll = Task { [weak self] in
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.reload()
        }
    }
    private func discard(_ job: BackupRecord, quietly: Bool = false) {
        discarded.insert(job.id); let account = state.account
        Task { [weak self, repository] in
            let result = await repository.discard(account: account, job: job)
            guard !quietly, let self else { return }
            if case .failure(let failure) = result { self.state.failure = failure } else { self.reload() }
        }
    }
    private func observe() {
        guard observer == nil else { return }
        let account = state.account, current = epoch
        observer = Task { [weak self, repository] in
            let observation = await repository.observe(account: account)
            for await event in observation.stream {
                guard !Task.isCancelled, let self, self.epoch == current else { break }
                switch event {
                case .invalidated: self.state.attended = true; self.reload()
                case .failed(let failure): self.state.attended = false; self.state.failure = failure
                }
            }
            await observation.stop()
            if let self, self.epoch == current { self.observer = nil; self.state.attended = false }
        }
    }
    private func stop() {
        epoch &+= 1; readID &+= 1; verifying = nil
        read?.cancel(); work?.cancel(); observer?.cancel(); poll?.cancel(); observer = nil; poll = nil
        let account = state.account, step = state.step
        state = BackupState(account: account)
        // A finished new-install restore stays visible; every other step restarts from the overview.
        if case .restored = step { state.step = step }
    }
    public func settleWork() async { await work?.value; await read?.value }
    deinit { read?.cancel(); work?.cancel(); observer?.cancel(); poll?.cancel() }
}
