// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureOnboarding
private actor FlowFake: OnboardingRepository, NodeRepository {
    let gate: MutationGate?
    private let confirmSucceeds: Bool
    init(gate: MutationGate? = nil, confirmSucceeds: Bool = false) { self.gate = gate; self.confirmSucceeds = confirmSucceeds }

    private(set) var origins: [String] = []
    private(set) var saved: [NodeRecord] = []
    private(set) var confirmations = 0
    private(set) var cancellations = 0
    func list() -> RepositoryResult<[NodeRecord]> { .success([]) }
    func inspect(_ origin: String) -> RepositoryResult<NodeRecord> { origins.append(origin); return .success(NodeRecord(id: "node", origin: origin, fingerprint: "fingerprint", publicKey: "observed-key")) }
    func save(_ node: NodeRecord, expectedPublicKey: String, operationID: String) -> RepositoryResult<Void> { saved.append(node); return .success(()) }
    func setDefault(_ node: NodeRecord, operationID: String) -> RepositoryResult<Void> { .success(()) }
    func begin(name: String, nodeID: String?) -> RepositoryResult<CeremonyMetadata> { .success(CeremonyMetadata(id: "ceremony", expiresInMilliseconds: 60_000)) }
    func showPhrase() -> RepositoryResult<RecoveryDisplay> { .failure(.unsupported) }
    func hideAndChallenge() -> RepositoryResult<[Int]> { .success([3, 7, 11]) }
    func confirmationUnresolved() async -> Bool { confirmations > 0 && !confirmSucceeds }
    func confirm(_ submission: SensitiveSubmission) async -> RepositoryResult<AccountRecord> { confirmations += 1; if let gate { await gate.wait() }; submission.erase(); return confirmSucceeds ? .success(AccountRecord(id: "new-account", displayName: "New account", isLocked: false)) : .failure(.outcomeUnknown) }
    func beginRecovery(accountID: String) -> RepositoryResult<CeremonyMetadata> { .success(CeremonyMetadata(id: "recovery", expiresInMilliseconds: 60_000, anchor: "fingerprint")) }
    func confirmRecovery(anchor: String, submission: SensitiveSubmission) -> RepositoryResult<AccountRecord> { confirmations += 1; submission.erase(); return .success(AccountRecord(id: "account", displayName: "Account", isLocked: false)) }
    func unlock(accountID: String, submission: SensitiveSubmission) -> RepositoryResult<AccountRecord> { submission.erase(); return .failure(.locked) }
    func cancel() -> RepositoryResult<Void> { cancellations += 1; return .success(()) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct OnboardingViewModelTests {
    @Test func concealAfterConfirmationDispatchKeepsRepositoryFenceAfterCleanup() async {
        let gate = MutationGate(), fake = FlowFake(gate: gate)
        defer { gate.release() }
        var state = OnboardingState(stage: .localUnlock); state.positions = [3,7,11]
        let model = OnboardingViewModel(repository: fake, nodes: fake, state: state, emit: { _ in })
        model.send(.submit(SensitiveSubmission(values: [:])))
        var dispatched = gate.entered.stream.makeAsyncIterator(); _ = await dispatched.next()
        model.send(.conceal); gate.release(); await model.settle()
        #expect(model.state.confirmationConsumed); #expect(model.state.failure == .outcomeUnknown)
        model.send(.create); model.send(.nameChanged("Fresh")); model.send(.beginCreation); await model.settle()
        #expect(model.state.failure == .outcomeUnknown); #expect(await fake.confirmations == 1)
    }
    @Test func originMustBeReviewedBeforeNetworkAndSavedKeyIsExact() async {
        let fake = FlowFake(); let model = OnboardingViewModel(repository: fake, nodes: fake, emit: { _ in })
        model.send(.customNode); model.send(.addressChanged("example.org/invite?token=secret")); model.send(.checkAddress)
        #expect(model.state.stage == .normalizedAddress); #expect(await fake.origins.isEmpty)
        model.send(.inspectOrigin); await model.settle()
        #expect(await fake.origins == ["https://example.org"])
        model.send(.expectedNodeKeyChanged("observed-key")); model.send(.reviewNodeKey); model.send(.saveNode); await model.settle()
        #expect(await fake.saved.first?.publicKey == "observed-key")
        #expect(model.state.stage == .saved)
    }
    @Test func plainDiscoveryRequiresMatchingOperatorKeyBeforeSavingOrCreation() async {
        let fake = FlowFake(); let model = OnboardingViewModel(repository: fake, nodes: fake, emit: { _ in })
        model.send(.create); model.send(.nameChanged("Account")); model.send(.beginCreation); await model.settle()
        #expect(model.state.failure == .nodeRequired)
        model.send(.customNode); model.send(.addressChanged("http://example.org:80/path?query=1")); model.send(.checkAddress)
        #expect(model.state.normalized?.origin == "http://example.org")
        model.send(.inspectOrigin); await model.settle()
        model.send(.expectedNodeKeyChanged("different")); model.send(.saveNode); await model.settle()
        #expect(model.state.failure == .nodeKeyMismatch); #expect(await fake.saved.isEmpty)
        model.send(.expectedNodeKeyChanged("observed-key")); model.send(.reviewNodeKey); model.send(.saveNode); await model.settle()
        #expect(await fake.saved.count == 1); #expect(model.state.nodes.first?.pinSource == "operator")
        #expect(model.state.nodes.first?.canCreateAccount == true)
        model.send(.create); model.send(.beginCreation); await model.settle()
        #expect(model.state.stage == .savePhrase)
    }
    @Test func discoveryKeyIsNeverPresentationCopyAndFingerprintNeedsIndependentEntry() async {
        let fake = FlowFake(); var state = OnboardingState(stage: .identity)
        let key = String(repeating: "k", count: 200)
        state.candidate = NodeRecord(id: "node", origin: "https://example.org", fingerprint: "fp", publicKey: key)
        let vm = OnboardingViewModel(repository: fake, nodes: fake, state: state, emit: { _ in })
        #expect(vm.state.visibleNodeFingerprint == nil)
        vm.send(.saveNode); await vm.settle(); #expect(await fake.saved.isEmpty)
        vm.send(.expectedNodeKeyChanged("mismatch")); vm.send(.reviewNodeKey)
        #expect(vm.state.failure == .nodeKeyMismatch); #expect(vm.state.visibleNodeFingerprint == nil)
        vm.send(.expectedNodeKeyChanged(key)); #expect(vm.state.expectedNodeKey == key)
        #expect(vm.state.visibleNodeFingerprint == nil)
        vm.send(.reviewNodeKey); #expect(vm.state.visibleNodeFingerprint == "fp")
        #expect(await fake.saved.isEmpty)
        vm.send(.expectedNodeKeyChanged("changed")); #expect(vm.state.visibleNodeFingerprint == nil)
        vm.send(.saveNode); await vm.settle(); #expect(await fake.saved.isEmpty)
    }
    @Test func successfulCreationEmitsNotificationOfferOnlyAfterDone() async {
        let fake = FlowFake(confirmSucceeds: true)
        var state = OnboardingState()
        state.nodes = [NodeRecord(id: "node", origin: "https://example.org", isConfirmed: true, pinSource: "operator")]
        state.selectedNodeID = "node"
        var events: [OnboardingEvent] = []
        let vm = OnboardingViewModel(repository: fake, nodes: fake, state: state, emit: { events.append($0) })
        vm.send(.create); vm.send(.nameChanged("New account")); vm.send(.beginCreation); await vm.settle()
        #expect(events.isEmpty)
        vm.send(.hidePhrase); await vm.settle(); vm.send(.continueUnlock)
        vm.send(.submit(SensitiveSubmission(values: [:]))); await vm.settle()
        #expect(vm.state.stage == .complete); #expect(!events.contains { if case .accountCreated = $0 { true } else { false } })
        vm.send(.done)
        #expect(events.contains { if case .accountCreated(let account) = $0 { account.id == "new-account" } else { false } })
    }
    @Test func notificationOfferEventIsOnlyForCreationNotUnlockOrRecovery() {
        let fake = FlowFake()
        for created in [false, true] {
            var state = OnboardingState(stage: .complete); state.creatingAccount = created
            let account = AccountRecord(id: "account", displayName: "Account", isLocked: false)
            state.completedAccount = account
            var events: [OnboardingEvent] = []
            let vm = OnboardingViewModel(repository: fake, nodes: fake, state: state, emit: { events.append($0) })
            vm.send(.done)
            #expect(events == [created ? .accountCreated(account) : .completed(account)])
        }
    }
    @Test func confirmationIsOneAttemptAndUnknownOutcomeDoesNotRetry() async {
        let fake = FlowFake(); var state = OnboardingState(stage: .localUnlock); state.positions = [3,7,11]
        let model = OnboardingViewModel(repository: fake, nodes: fake, state: state, emit: { _ in })
        model.send(.submit(SensitiveSubmission(values: [:]))); await model.settle()
        #expect(model.state.failure == .outcomeUnknown)
        model.send(.submit(SensitiveSubmission(values: [:]))); await model.settle()
        #expect(await fake.confirmations == 1)
    }
    @Test func recoveryRequiresExplicitFingerprintConfirmation() async {
        let fake = FlowFake(); let model = OnboardingViewModel(repository: fake, nodes: fake, emit: { _ in })
        model.send(.recover); model.send(.recoveryAccountChanged("existing-account")); model.send(.beginRecovery); await model.settle()
        model.send(.submit(SensitiveSubmission(values: [:]))); await model.settle()
        #expect(await fake.confirmations == 0)
        model.send(.checkAnchor(true)); model.send(.submit(SensitiveSubmission(values: [:]))); await model.settle()
        #expect(model.state.stage == .complete)
        model.send(.conceal); await model.settle()
        #expect(model.state.metadata == nil); #expect(model.state.displayID == nil)
        #expect(await fake.cancellations == 1)
    }
    @Test func explicitExpiryCancelsBackendAndConcealsAllSecretState() async {
        let fake = FlowFake(); var state = OnboardingState()
        state.nodes = [NodeRecord(id: "node", origin: "https://example.org", isConfirmed: true, pinSource: "operator")]; state.selectedNodeID = "node"
        let model = OnboardingViewModel(repository: fake, nodes: fake, state: state, emit: { _ in })
        model.send(.create); model.send(.nameChanged("Account")); model.send(.beginCreation); await model.settle()
        #expect(model.state.stage == .savePhrase)
        model.send(.expired); await model.settle()
        #expect(model.state.metadata == nil); #expect(model.state.displayID == nil)
        #expect(await fake.cancellations == 1)
    }
    @Test func unavailableRepositoryNeverCompletesCreation() async {
        let model = OnboardingViewModel(repository: UnavailableOnboardingRepository(), nodes: UnavailableNodeRepository(), emit: { _ in })
        model.send(.create); model.send(.nameChanged("Account")); model.send(.beginCreation); await model.settle()
        #expect(model.state.failure == .nodeRequired); #expect(model.state.completedAccount == nil)
    }
    @Test func everyScreenHasStableIdentityAndSecretActionsAreRedacted() {
        #expect(OnboardingPreviews.states.count == 25)
        #expect(Set(OnboardingPreviews.states.map(\.stage.board)).count == 25)
        #expect(String(describing: OnboardingAction.submit(SensitiveSubmission(values: ["phrase":"private"]))) == "submit")
    }
}
