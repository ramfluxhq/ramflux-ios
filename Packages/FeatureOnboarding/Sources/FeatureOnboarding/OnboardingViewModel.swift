// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class OnboardingViewModel {
    public private(set) var state: OnboardingState
    private let repository: any OnboardingRepository
    private let nodes: any NodeRepository
    private let emit: @MainActor (OnboardingEvent) -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var network: Task<Void, Never>?
    /// How long the completion step follows networking, and how often it asks.
    @ObservationIgnored var networkWatch: (attempts: Int, interval: Duration) = (45, .seconds(2))
    @ObservationIgnored private var unresolvedConfirmation = false
    @ObservationIgnored private var generation: UInt64 = 0
    /// The state a cleanup returns to: the plain start, or the unlock step of a known account.
    @ObservationIgnored private let base: OnboardingState
    public init(repository: any OnboardingRepository, nodes: any NodeRepository, state: OnboardingState = OnboardingState(), emit: @escaping @MainActor (OnboardingEvent) -> Void) {
        self.repository = repository; self.nodes = nodes; self.state = state; self.base = state; self.emit = emit
    }
    public func send(_ action: OnboardingAction) {
        switch action {
        case .disappeared, .conceal, .cancel: cleanup(dismiss: action == .cancel); return
        case .expired: cleanup(dismiss: false); state.failure = .unavailableResource("onboarding.failure.setupExpired"); return
        default: break
        }
        guard !state.busy else { if case .submit(let input) = action { input.erase() }; return }
        state.failure = nil
        switch action {
        case .appeared: run { [nodes] in .nodes(await nodes.list()) }
        case .nameChanged(let value): state.name = String(value.prefix(256))
        case .expectedNodeKeyChanged(let value): state.expectedNodeKey = value.trimmingCharacters(in: .whitespacesAndNewlines); state.reviewedNode = nil
        case .addressChanged(let value): state.address = String(value.prefix(2048)); state.candidate = nil; state.reviewedNode = nil; state.expectedNodeKey = ""
        case .recoveryAccountChanged(let value): if state.knownAccountName == nil, !state.recoversLockedAccount { state.recoveryAccount = String(value.prefix(256)) }
        case .forgetKnownAccount: if state.knownAccountName != nil, !state.recoveryAccount.isEmpty { state.confirmingForget = true }
        case .confirmForget(let confirmed):
            state.confirmingForget = false
            if confirmed, state.knownAccountName != nil, !state.recoveryAccount.isEmpty { emit(.forgetAccount(state.recoveryAccount)) }
        case .nodeSelected(let id): if state.nodes.contains(where: { $0.id == id && $0.canCreateAccount }) { state.selectedNodeID = id }
        case .unlockExisting: state.creatingAccount = false; state.unlockingSavedAccount = true; state.showingUnlockInfo = false; state.stage = .localUnlock
        case .getStarted: if state.stage == .connection { state.stage = .welcome }
        case .existingAccount: state.creatingAccount = false; state.stage = .start
        case .unlockInfo(let visible): state.showingUnlockInfo = visible
        case .create: state.creatingAccount = true; state.unlockingSavedAccount = false; state.stage = .create
        case .recover: state.creatingAccount = false; state.stage = .recover
        case .restoreBackup: if !state.recoversLockedAccount { emit(.restoreBackup) }
        case .link:
            state.stage = .link
            state.failure = .unavailableResource("onboarding.failure.pairingUnavailable")
        case .customNode: state.reviewedNode = nil; state.candidate = nil; state.expectedNodeKey = ""; state.stage = .address
        case .checkAddress:
            do { state.normalized = try NodeAddress(state.address); state.stage = .normalizedAddress }
            catch { state.failure = .invalidInput }
        case .inspectOrigin:
            guard let normalized = state.normalized else { return }
            state.stage = .verifying
            run { [nodes] in .node(await nodes.inspect(normalized.origin)) }
        case .reviewNodeKey:
            guard state.canReviewFingerprint, let candidate = state.candidate, candidate.fingerprint != nil else { state.failure = .nodeKeyMismatch; return }
            state.reviewedNode = candidate
        case .saveNode:
            guard let candidate = state.candidate, state.reviewedNode == candidate, candidate.fingerprint != nil else { state.failure = .nodeKeyMismatch; return }
            guard !state.expectedNodeKey.isEmpty, state.expectedNodeKey == candidate.publicKey else { state.failure = .nodeKeyMismatch; return }
            let expectedKey = state.expectedNodeKey
            state.stage = .saving
            run { [nodes] in .saved(await nodes.save(candidate, expectedPublicKey: expectedKey, operationID: UUID().uuidString)) }
        case .setDefault:
            guard let candidate = state.candidate else { return }
            run { [nodes] in .defaultSet(await nodes.setDefault(candidate, operationID: UUID().uuidString)) }
        case .beginCreation:
            guard !unresolvedConfirmation else { state.failure = .outcomeUnknown; return }
            guard !state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { state.failure = .invalidInput; return }
            guard let node = state.selectedNodeID, state.nodes.contains(where: { $0.id == node && $0.canCreateAccount }) else { state.failure = .nodeRequired; return }
            let name = state.name
            run { [repository] in .began(await repository.begin(name: name, nodeID: node)) }
        case .showPhrase: run { [repository] in .display(await repository.showPhrase()) }
        case .hidePhrase:
            emit(.revokeRecovery); state.displayID = nil
            run { [repository] in .challenge(await repository.hideAndChallenge()) }
        case .beginRecovery:
            guard !unresolvedConfirmation else { state.failure = .outcomeUnknown; return }
            guard !state.recoveryAccount.isEmpty else { state.failure = .invalidInput; return }
            let id = state.recoveryAccount
            run { [repository] in .recovery(await repository.beginRecovery(accountID: id)) }
        case .checkAnchor(let value): state.anchorChecked = value
        case .continueUnlock: if state.stage == .confirmPhrase { state.stage = .localUnlock }
        case .submit(let input):
            guard !state.confirmationConsumed else { input.erase(); return }
            // A code the SDK would refuse must not spend the single-attempt confirmation.
            if let issue = input.accountCodeIssue { input.erase(); state.failure = .accountCode(issue); return }
            if state.unlockingSavedAccount {
                guard !state.recoveryAccount.isEmpty else { input.erase(); state.failure = .invalidInput; return }
                let id = state.recoveryAccount
                run { [repository] in .confirmed(await repository.unlock(accountID: id, submission: input)) }
            } else if state.stage == .recover {
                guard state.anchorChecked, let anchor = state.metadata?.anchor else { input.erase(); state.failure = .invalidInput; return }
                state.confirmationConsumed = true
                run { [repository] in .confirmed(await repository.confirmRecovery(anchor: anchor, submission: input)) }
            } else {
                guard state.stage == .localUnlock, state.positions.count == 3 else { input.erase(); return }
                state.confirmationConsumed = true
                run { [repository] in .confirmed(await repository.confirm(input)) }
            }
        case .done: if let account = state.completedAccount { emit(state.creatingAccount ? .accountCreated(account) : .completed(account)) }
        default: break
        }
    }
    private enum Completion: Sendable {
        case nodes(RepositoryResult<[NodeRecord]>), node(RepositoryResult<NodeRecord>), saved(RepositoryResult<Void>), defaultSet(RepositoryResult<Void>)
        case began(RepositoryResult<CeremonyMetadata>), display(RepositoryResult<RecoveryDisplay>), challenge(RepositoryResult<[Int]>)
        case recovery(RepositoryResult<CeremonyMetadata>), confirmed(RepositoryResult<AccountRecord>)
    }
    private func run(_ operation: @escaping @Sendable () async -> Completion) {
        generation &+= 1; let epoch = generation; state.busy = true
        work = Task { [weak self] in
            let result = await operation()
            guard !Task.isCancelled, let self, self.generation == epoch else {
                if case .display(.success(let display)) = result { display.erase() }; return
            }
            self.state.busy = false; self.apply(result)
        }
    }
    private func apply(_ completion: Completion) {
        if case .confirmed(.failure(.outcomeUnknown)) = completion { unresolvedConfirmation = true }
        switch completion {
        case .nodes(.success(let nodes)): state.nodes = nodes; state.selectedNodeID = nodes.first(where: { $0.isDefault && $0.canCreateAccount })?.id
        case .node(.success(let node)): state.reviewedNode = nil; state.expectedNodeKey = ""; state.candidate = node; state.stage = .identity
        case .saved(.success):
            if let candidate = state.candidate {
                let confirmed = NodeRecord(id: candidate.id, origin: candidate.origin, fingerprint: candidate.fingerprint,
                    publicKey: candidate.publicKey, isDefault: candidate.isDefault, enabled: candidate.enabled,
                    isConfirmed: true, pinSource: "operator")
                state.candidate = confirmed; state.nodes.removeAll { $0.id == confirmed.id }; state.nodes.append(confirmed)
                state.selectedNodeID = confirmed.id
            }
            state.stage = .saved
        case .defaultSet(.success): state.selectedNodeID = state.candidate?.id; state.stage = .saved
        case .began(.success(let metadata)):
            state.metadata = metadata; state.stage = .savePhrase; scheduleExpiry(metadata)
        case .display(.success(let display)):
            let id = UUID(); state.displayID = id; emit(.presentRecovery(id, display))
        case .challenge(.success(let positions)): state.positions = positions; state.stage = .confirmPhrase
        case .recovery(.success(let metadata)): state.metadata = metadata; scheduleExpiry(metadata)
        case .confirmed(.success(let account)):
            expiry?.cancel(); state.completedAccount = account; state.stage = .complete
            if account.networking != .live { watchNetwork(account) }
        case .confirmed(.failure(let error)) where state.stage == .recover && error != .outcomeUnknown:
            recoveryRefused(error)
        case .nodes(.failure(let error)), .node(.failure(let error)), .saved(.failure(let error)), .defaultSet(.failure(let error)), .began(.failure(let error)), .display(.failure(let error)), .challenge(.failure(let error)), .recovery(.failure(let error)), .confirmed(.failure(let error)):
            state.failure = (error == .failed || error == .invalidData) ? .onboardingProtocol : error
            if state.stage == .verifying { state.stage = .connectionFailed }
            if state.stage == .saving { state.stage = .saveFailed }
        }
    }
    /// A recovery confirmation the SDK refused with a named reason. The ceremony is gone, so the flow starts again at
    /// step 1 with the reason shown. In the lock cover, the refusals that move the lock screen (the code wait after an
    /// accepted phrase, a wrong code, exhausted checks) hand over to the host, which closes the recovery and reads the state.
    private func recoveryRefused(_ error: AppFailure) {
        expiry?.cancel(); expiry = nil
        state.confirmationConsumed = false; state.metadata = nil; state.anchorChecked = false
        state.failure = error
        guard state.recoversLockedAccount else { return }
        switch error {
        case .accountCodeWait, .accountCode(.retryLater), .accountCode(.wrong), .accountCode(.attemptsExhausted): emit(.lockRecoveryEnded(error))
        default: break
        }
    }
    private func scheduleExpiry(_ metadata: CeremonyMetadata) {
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(metadata.expiresInMilliseconds)) }
            catch { return }
            self?.send(.expired)
        }
    }
    /// Follows `account.status` after creation or unlock until the SDK reports networking live, so the
    /// completion step shows the real state instead of the confirmation's snapshot.
    private func watchNetwork(_ account: AccountRecord) {
        network?.cancel(); state.watchingNetwork = true
        let plan = networkWatch
        network = Task { [weak self, repository] in
            for _ in 0..<plan.attempts {
                do { try await Task.sleep(for: plan.interval) } catch { return }
                guard case .success(let networking) = await repository.networking(accountID: account.id) else { continue }
                guard let self, !Task.isCancelled, self.state.completedAccount?.id == account.id else { return }
                if networking == .live {
                    self.state.completedAccount = AccountRecord(id: account.id, displayName: account.displayName, isLocked: account.isLocked, networking: .live)
                    self.state.watchingNetwork = false; return
                }
            }
            self?.state.watchingNetwork = false
        }
    }
    /// Test barrier for the networking watch.
    func settleNetwork() async { await network?.value }
    private func cleanup(dismiss: Bool) {
        network?.cancel(); network = nil
        generation &+= 1; let epoch = generation
        emit(.revokeRecovery); expiry?.cancel(); expiry = nil
        let previous = work; previous?.cancel()
        state = base; state.busy = true
        work = Task { [weak self, repository] in
            await previous?.value
            let result = await repository.cancel()
            let unresolved = await repository.confirmationUnresolved()
            guard let self, self.generation == epoch else { return }
            self.state.busy = false
            self.unresolvedConfirmation = unresolved
            self.state.confirmationConsumed = unresolved
            if unresolved { self.state.failure = .outcomeUnknown }
            if case .failure(let error) = result { self.state.failure = error; self.state.confirmationConsumed = true }
            if dismiss { self.emit(.dismissed) }
        }
    }
    public func settle() async { await work?.value }
    deinit { work?.cancel(); expiry?.cancel(); network?.cancel() }
}
