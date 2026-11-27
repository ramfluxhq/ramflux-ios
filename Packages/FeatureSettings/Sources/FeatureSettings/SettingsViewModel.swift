// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
import RamfluxCore
@Observable @MainActor public final class SettingsViewModel {
    public private(set) var state: SettingsState
    private let account: String?
    private let repository: any SettingsRepository
    private let nodes: any NodeRepository
    private let preferences: any PreferencesRepository
    private let emit: (SettingsEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var sideTask: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    /// The Username page's tasks. Bumped when the account is locked, signed out, removed or the page disappears,
    /// so a late reply for another or a locked account is dropped.
    @ObservationIgnored private var usernameEpoch: UInt64 = 0
    @ObservationIgnored private var claimTask: Task<Void, Never>?
    @ObservationIgnored private var usernameRead: Task<Void, Never>?
    /// Tags each status read; a read whose ticket is no longer current (a claim started or finished meanwhile) is dropped.
    @ObservationIgnored private var usernameTicket: UInt64 = 0
    @ObservationIgnored private var lastUsernameRead: ContinuousClock.Instant?
    /// The account-code request core opened for a weakening change; resumed once with the code, or nil.
    @ObservationIgnored private var codeAnswer: CheckedContinuation<SecretBytes?, Never>?
    @ObservationIgnored private var codeTimer: Task<Void, Never>?
    /// The user closed the code sheet (or the screen left): a refusal that follows is not shown as an error.
    @ObservationIgnored private var userDismissedCode = false
    public init(repository: any SettingsRepository, nodes: any NodeRepository, preferences: any PreferencesRepository,
                account: String?, state: SettingsState = SettingsState(), emit: @escaping (SettingsEvent) -> Void) {
        self.repository = repository; self.nodes = nodes; self.preferences = preferences; self.account = account; self.state = state; self.emit = emit
        self.state.accountOpen = account != nil
    }
    public func send(_ action: SettingsAction) {
        switch action {
        case .appeared, .refresh:
            refresh(); observe()
            // A configure in flight answers with its own record; a read started now could land after it with the old one.
            if state.route == .appLock, !state.busy { readAppLock() }
            if state.route == .username { readUsername() }
        case .configureAppLock(let enabled, let timeout):
            guard let account, !state.busy, state.appLock?.state != .unavailable else { return }
            // While the code is throttled or used up, a weakening change cannot succeed: nothing is sent.
            if weakensAppLock(enabled: enabled, timeout: timeout), appLockCodeBlocked { return }
            state.busy = true; state.failure = nil; state.appLockTurningOff = !enabled; let current = epoch; userDismissedCode = false
            mutation = Task { [weak self, repository] in
                // Core asks for the account code only for a weakening change; the answer comes from the sheet below.
                let result = await repository.configureAppLock(account: account, enabled: enabled, timeoutMilliseconds: timeout,
                    credentials: { [weak self] action in await self?.answerAccountCode(action) }, operationID: UUID().uuidString)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                self.state.busy = false
                switch result {
                case .success(let record): self.apply(record); self.emit(.appLockChanged(record.enabled))
                case .failure(let failure):
                    // A dismissed sheet is a refusal the user chose: the stored state is shown again, with no error text.
                    self.state.failure = failure == .accountCode(.reauthRequired) && self.userDismissedCode ? nil : failure
                    self.readAppLock()
                }
            }
        case .submitAccountCode(let input):
            guard state.codePrompt, codeAnswer != nil else { input.erase(); return }
            if let issue = input.accountCodeIssue { input.erase(); state.failure = .accountCode(issue); return }
            guard let code = input.takeAccountCode() else { input.erase(); return }
            finishAccountCode(code)
        case .cancelAccountCode:
            userDismissedCode = true; finishAccountCode(nil)
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
        case .requestPolicy(let autoAccept):
            guard account != nil else { return }
            dispatch(PendingSettingsMutation(change: .requestPolicy(autoAccept: autoAccept), operationID: UUID().uuidString))
        case .startChangeCode: guard account != nil, !state.busy else { return }; state.failure = nil; state.codeChanged = false; state.changingCode = true
        case .cancelChangeCode: if !state.busy { state.changingCode = false }
        case .submitChangeCode(let input):
            guard let account, state.changingCode, !state.busy else { input.erase(); return }
            if let issue = input.accountCodeIssue { input.erase(); state.failure = .accountCode(issue); return }
            state.busy = true; state.failure = nil; let current = epoch
            mutation = Task { [weak self, repository] in
                let result = await repository.changeCode(account: account, credentials: input, operationID: UUID().uuidString)
                guard !Task.isCancelled, let self, self.epoch == current else { return }
                self.state.busy = false
                switch result {
                case .success: self.state.changingCode = false; self.state.codeChanged = true
                case .failure(let failure): self.state.failure = failure
                }
            }
        case .openSystemLanguage: emit(.openSystemSettings)
        case .requestRevoke(let id):
            guard !state.busy, !state.unknownMutation, let device = state.snapshot.devices.first(where: { $0.id == id && !$0.isLocal }) else { return }; state.pendingRevoke = device
        case .confirmRevoke(let id):
            guard account != nil, let device = state.pendingRevoke, device.id == id else { return }
            dispatch(PendingSettingsMutation(change: .revoke(device), operationID: UUID().uuidString))
        case .cancelRevoke: if !state.busy { state.pendingRevoke = nil }
        case .lock:
            guard account != nil else { return }
            clearUsername()
            dispatch(PendingSettingsMutation(change: .lock, operationID: UUID().uuidString))
        case .signOut:
            guard account != nil else { return }
            clearUsername()
            dispatch(PendingSettingsMutation(change: .signOut, operationID: UUID().uuidString))
        case .requestRemoveLocal: if account != nil, !state.busy, !state.unknownMutation { state.failure = nil; state.confirmingRemoval = true }
        case .confirmRemoveLocal:
            guard account != nil, state.confirmingRemoval else { return }
            clearUsername()
            dispatch(PendingSettingsMutation(change: .removeLocal, operationID: UUID().uuidString))
        case .setDefault(let id):
            guard let node = state.snapshot.nodes.first(where: { $0.id == id }) else { return }
            dispatch(PendingSettingsMutation(change: .setDefault(node), operationID: UUID().uuidString))
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .dismissModal:
            if state.codePrompt { userDismissedCode = true; finishAccountCode(nil) }
            state.pendingRevoke = nil; if !state.busy { state.changingCode = false; state.confirmingRemoval = false; state.claim = nil }
        case .startClaimUsername:
            guard account != nil, !state.busy else { return }
            state.failure = nil; state.claim = UsernameClaim()
        case .claimNameChanged(let name):
            guard !state.busy, var claim = state.claim, claim.step == .name else { return }
            claim.name = name; state.claim = claim
        case .continueClaimUsername:
            guard !state.busy, var claim = state.claim, claim.step == .name, UsernameInput.name(claim.name) != nil else { return }
            state.failure = nil; claim.step = .phrase; state.claim = claim
        case .cancelClaimUsername:
            if !state.busy { state.claim = nil; state.failure = nil }
        case .conceal:
            // Leaving the active scene closes the claim sheet (dropping it erases the phrase field) and cancels a claim in flight, even while busy.
            if state.codePrompt { userDismissedCode = true; finishAccountCode(nil) }
            guard state.claim != nil else { return }
            abandonClaim(); state.claim = nil; state.failure = nil
        case .submitClaimUsername(let input):
            guard let account, let claim = state.claim, claim.step == .phrase, !state.busy else { input.erase(); return }
            state.busy = true; state.failure = nil; supersedeUsernameRead()
            let name = claim.name, current = usernameEpoch
            claimTask = Task { [weak self, repository] in
                let result = await repository.claimUsername(account: account, name: name, phrase: input, operationID: UUID().uuidString)
                guard !Task.isCancelled, let self, self.usernameEpoch == current else { return }
                self.claimTask = nil; self.state.busy = false; self.supersedeUsernameRead()
                switch result {
                case .success(let status):
                    self.state.username = status; self.state.claim = nil
                case .failure(let failure):
                    self.state.failure = failure
                    // A name the directory refuses goes back to the name step; a wrong phrase stays on the phrase step.
                    if case .unavailableResource(let key) = failure, key == "username.claim.taken" || key == "username.claim.invalid" {
                        self.state.claim?.step = .name
                    }
                }
            }
        case .refreshUsername:
            guard account != nil, !state.usernameLoading, !state.busy else { return }
            let now = ContinuousClock.now
            if let last = lastUsernameRead, now < last.advanced(by: .seconds(2)) { return }
            readUsername(operationID: state.username?.state == .pending ? state.username?.operationID : nil)
        case .reconcileOriginal(let id):
            if let pending = state.pendingMutation, pending.operationID == id, !state.busy { dispatch(pending, reconciling: true) }
        case .disappeared:
            sideTask?.cancel()
            userDismissedCode = true; finishAccountCode(nil)
            epoch &+= 1; readID &+= 1; watchID &+= 1; read?.cancel(); mutation?.cancel(); observer?.cancel(); observer = nil; pendingRefresh = false
            clearUsername()
            let unknown = state.unknownMutation || state.busy, route = state.route, appearance = state.appearance
            state = SettingsState(route: route); state.appearance = appearance; state.unknownMutation = unknown; state.accountOpen = account != nil
        }
    }
    /// The App lock page reads the SDK's state of the active account (none is read without an open account).
    private func readAppLock() {
        guard let account else { return }
        sideTask?.cancel()
        sideTask = Task { [weak self, repository] in
            let result = await repository.appLock(account: account)
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let record): self.apply(record)
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    /// Stores the SDK's app-lock state and the monotonic moment its account-code wait ends. Nothing else is kept.
    private func apply(_ record: AppLockRecord) {
        state.appLock = record
        state.codeRetryDeadline = record.codeRetryAfterMilliseconds.map { ContinuousClock.now.advanced(by: .milliseconds(Int(min($0, 86_400_000)))) }
    }
    /// A change that lowers the lock's strength: the lock is on and it is turned off, or its timeout gets longer.
    private func weakensAppLock(enabled: Bool, timeout: UInt64) -> Bool {
        guard let record = state.appLock, record.enabled else { return false }
        return !enabled || timeout > record.timeoutMilliseconds
    }
    /// The account-code checks are throttled (the wait has not ended) or used up. Strengthening is never blocked.
    private var appLockCodeBlocked: Bool {
        if state.appLock?.codeAttemptsExhausted == true { return true }
        guard let deadline = state.codeRetryDeadline else { return false }
        return ContinuousClock.now < deadline
    }
    /// Core asked for the account code of a weakening change: the sheet opens and the answer is the code, or nil when
    /// the sheet is closed, times out or the screen leaves. One request is open at a time; core never gets a second.
    private func answerAccountCode(_ action: CredentialAction) async -> SecretBytes? {
        guard action == .unlock, account != nil, codeAnswer == nil else { return nil }
        return await withCheckedContinuation { continuation in
            codeAnswer = continuation
            state.codePrompt = true
            codeTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.finishAccountCode(nil)
            }
        }
    }
    /// Closes the code sheet and resumes the open request once. A secret that finds no request is erased.
    private func finishAccountCode(_ secret: SecretBytes?) {
        codeTimer?.cancel(); codeTimer = nil
        state.codePrompt = false
        guard let continuation = codeAnswer else { secret?.erase(); return }
        codeAnswer = nil
        continuation.resume(returning: secret)
    }
    /// The username row asks the username directory (`username.status`): the claimed name, or the
    /// directory's refusal as an honest unavailable state.
    private func readUsername(operationID: String? = nil) {
        guard let account else { return }
        state.failure = nil; state.usernameLoading = true; lastUsernameRead = ContinuousClock.now
        let current = usernameEpoch
        usernameTicket &+= 1; let ticket = usernameTicket
        usernameRead?.cancel()
        usernameRead = Task { [weak self, repository] in
            let result = await repository.username(account: account, operationID: operationID)
            guard let self, !Task.isCancelled, self.usernameEpoch == current, self.usernameTicket == ticket else { return }
            self.usernameRead = nil; self.state.usernameLoading = false
            switch result {
            case .success(let status): self.state.username = status
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    /// Drops any username status read in flight: its reply no longer describes the page.
    private func supersedeUsernameRead() {
        usernameTicket &+= 1; usernameRead?.cancel(); usernameRead = nil; state.usernameLoading = false
    }
    /// Cancels a claim in flight. Its reply is dropped by the epoch and cancellation guards, so the page must not stay busy for it.
    private func abandonClaim() {
        guard claimTask != nil else { return }
        claimTask?.cancel(); claimTask = nil; state.busy = false
    }
    /// Drops the claim sheet and the username status of the account being locked, signed out or removed.
    /// A claim still running is cancelled and releases the busy state, so the lock, sign-out or removal that follows runs.
    private func clearUsername() {
        usernameEpoch &+= 1; abandonClaim(); sideTask?.cancel(); supersedeUsernameRead()
        state.claim = nil; state.username = nil
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
            case .success:
                self.state.pendingRevoke = nil; self.state.confirmingRemoval = false
                if [.lock, .signOut, .removeLocal].contains(attempt.change) { self.emit(.locked) } else { self.refresh() }
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
            case .updated: self.state.pendingRevoke = nil; self.refresh()
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
