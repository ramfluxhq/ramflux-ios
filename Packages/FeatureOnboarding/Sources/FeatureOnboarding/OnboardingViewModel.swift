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
    @ObservationIgnored private var unresolvedConfirmation = false
    @ObservationIgnored private var generation: UInt64 = 0
    public init(repository: any OnboardingRepository, nodes: any NodeRepository, state: OnboardingState = OnboardingState(), emit: @escaping @MainActor (OnboardingEvent) -> Void) {
        self.repository = repository; self.nodes = nodes; self.state = state; self.emit = emit
    }
    public func send(_ action: OnboardingAction) {
        switch action {
        case .disappeared, .conceal, .cancel: cleanup(dismiss: action == .cancel); return
        case .expired: cleanup(dismiss: false); state.failure = .unavailableResource("FeatureOnboarding.copy.d59626702d22"); return
        default: break
        }
        guard !state.busy else { if case .submit(let input) = action { input.erase() }; return }
        state.failure = nil
        switch action {
        case .appeared: run { [nodes] in .nodes(await nodes.list()) }
        case .nameChanged(let value): state.name = String(value.prefix(256))
        case .expectedNodeKeyChanged(let value): state.expectedNodeKey = String(value.prefix(128))
        case .addressChanged(let value): state.address = String(value.prefix(2048)); state.candidate = nil
        case .recoveryAccountChanged(let value): state.recoveryAccount = String(value.prefix(256))
        case .nodeSelected(let id): if state.nodes.contains(where: { $0.id == id && $0.canCreateAccount }) { state.selectedNodeID = id }
        case .unlockExisting: state.unlockingSavedAccount = true; state.stage = .localUnlock
        case .create: state.unlockingSavedAccount = false; state.stage = .create
        case .recover: state.stage = .recover
        case .link:
            state.stage = .link
            state.failure = .unavailableResource("FeatureOnboarding.copy.5fca79c1258a")
        case .customNode: state.stage = .address
        case .checkAddress:
            do { state.normalized = try NodeAddress(state.address); state.stage = .normalizedAddress }
            catch { state.failure = .invalidInput }
        case .inspectOrigin:
            guard let normalized = state.normalized else { return }
            state.stage = .verifying
            run { [nodes] in .node(await nodes.inspect(normalized.origin)) }
        case .saveNode:
            guard let candidate = state.candidate, candidate.fingerprint != nil else { return }
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
        case .done: if let account = state.completedAccount { emit(.completed(account)) }
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
        case .node(.success(let node)): state.expectedNodeKey = ""; state.candidate = node; state.stage = .identity
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
        case .confirmed(.success(let account)): expiry?.cancel(); state.completedAccount = account; state.stage = .complete
        case .nodes(.failure(let error)), .node(.failure(let error)), .saved(.failure(let error)), .defaultSet(.failure(let error)), .began(.failure(let error)), .display(.failure(let error)), .challenge(.failure(let error)), .recovery(.failure(let error)), .confirmed(.failure(let error)):
            state.failure = (error == .failed || error == .invalidData) ? .onboardingProtocol : error
            if state.stage == .verifying { state.stage = .connectionFailed }
            if state.stage == .saving { state.stage = .saveFailed }
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
    private func cleanup(dismiss: Bool) {
        generation &+= 1; let epoch = generation
        emit(.revokeRecovery); expiry?.cancel(); expiry = nil
        let previous = work; previous?.cancel()
        state = OnboardingState(); state.busy = true
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
    deinit { work?.cancel(); expiry?.cancel() }
}
