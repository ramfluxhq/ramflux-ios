// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureOnboarding
private actor FlowFake: OnboardingRepository, NodeRepository {
    private(set) var origins: [String] = []
    private(set) var saved: [NodeRecord] = []
    private(set) var confirmations = 0
    private(set) var cancellations = 0
    func list() -> RepositoryResult<[NodeRecord]> { .success([]) }
    func inspect(_ origin: String) -> RepositoryResult<NodeRecord> { origins.append(origin); return .success(NodeRecord(id: "node", origin: origin, fingerprint: "fingerprint", publicKey: "observed-key")) }
    func save(_ node: NodeRecord, operationID: String) -> RepositoryResult<Void> { saved.append(node); return .success(()) }
    func setDefault(_ node: NodeRecord, operationID: String) -> RepositoryResult<Void> { .success(()) }
    func begin(name: String, nodeID: String?) -> RepositoryResult<CeremonyMetadata> { .success(CeremonyMetadata(id: "ceremony", expiresInMilliseconds: 60_000)) }
    func showPhrase() -> RepositoryResult<RecoveryDisplay> { .failure(.unsupported) }
    func hideAndChallenge() -> RepositoryResult<[Int]> { .success([3, 7, 11]) }
    func confirm(_ submission: SensitiveSubmission) -> RepositoryResult<AccountRecord> { confirmations += 1; submission.erase(); return .failure(.outcomeUnknown) }
    func beginRecovery(accountID: String) -> RepositoryResult<CeremonyMetadata> { .success(CeremonyMetadata(id: "recovery", expiresInMilliseconds: 60_000, anchor: "fingerprint")) }
    func confirmRecovery(anchor: String, submission: SensitiveSubmission) -> RepositoryResult<AccountRecord> { confirmations += 1; submission.erase(); return .success(AccountRecord(id: "account", displayName: "Account", isLocked: false)) }
    func unlock(accountID: String, submission: SensitiveSubmission) -> RepositoryResult<AccountRecord> { submission.erase(); return .failure(.locked) }
    func cancel() -> RepositoryResult<Void> { cancellations += 1; return .success(()) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct OnboardingViewModelTests {
    @Test func originMustBeReviewedBeforeNetworkAndSavedKeyIsExact() async {
        let fake = FlowFake(); let model = OnboardingViewModel(repository: fake, nodes: fake, emit: { _ in })
        model.send(.customNode); model.send(.addressChanged("example.org/invite?token=secret")); model.send(.checkAddress)
        #expect(model.state.stage == .normalizedAddress); #expect(await fake.origins.isEmpty)
        model.send(.inspectOrigin); await model.settle()
        #expect(await fake.origins == ["https://example.org"])
        model.send(.saveNode); await model.settle()
        #expect(await fake.saved.first?.publicKey == "observed-key")
        #expect(model.state.stage == .saved)
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
        #expect(model.state.metadata == nil); #expect(model.state.display == nil)
        #expect(await fake.cancellations == 1)
    }
    @Test func explicitExpiryCancelsBackendAndConcealsAllSecretState() async {
        let fake = FlowFake(); let model = OnboardingViewModel(repository: fake, nodes: fake, emit: { _ in })
        model.send(.create); model.send(.nameChanged("Account")); model.send(.beginCreation); await model.settle()
        #expect(model.state.stage == .savePhrase)
        model.send(.expired); await model.settle()
        #expect(model.state.metadata == nil); #expect(model.state.display == nil)
        #expect(await fake.cancellations == 1)
    }
    @Test func unavailableRepositoryNeverCompletesCreation() async {
        let model = OnboardingViewModel(repository: UnavailableOnboardingRepository(), nodes: UnavailableNodeRepository(), emit: { _ in })
        model.send(.create); model.send(.nameChanged("Account")); model.send(.beginCreation); await model.settle()
        #expect(model.state.failure == .sdkUnavailable); #expect(model.state.completedAccount == nil)
    }
    @Test func everyScreenHasStableIdentityAndSecretActionsAreRedacted() {
        #expect(OnboardingPreviews.states.count == 25)
        #expect(Set(OnboardingPreviews.states.map(\.stage.board)).count == 25)
        #expect(String(describing: OnboardingAction.submit(SensitiveSubmission(values: ["phrase":"private"]))) == "submit")
    }
}
