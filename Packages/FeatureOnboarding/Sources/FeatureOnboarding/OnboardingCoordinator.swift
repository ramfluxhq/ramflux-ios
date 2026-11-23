// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
@Observable @MainActor public final class OnboardingCoordinator {
    public let secureSlot = SecureRecoverySlot()
    private let repository: any OnboardingRepository
    private let nodes: any NodeRepository
    private let completion: (AccountRecord?) -> Void
    private let created: (AccountRecord) -> Void
    private let restoreBackup: () -> Void
    private let initialState: OnboardingState
    private let forget: (String) -> Void
    @ObservationIgnored public lazy var viewModel = OnboardingViewModel(repository: repository, nodes: nodes, state: initialState) { [weak self] event in
        switch event { case .accountCreated(let account): self?.completion(account); self?.created(account); case .completed(let account): self?.completion(account); case .dismissed: self?.completion(nil); case .presentRecovery(let id, let display): self?.secureSlot.install(id: id, display: display); case .revokeRecovery: self?.secureSlot.revoke(); case .restoreBackup: self?.restoreBackup(); case .forgetAccount(let id): self?.forget(id) }
    }
    public init(repository: any OnboardingRepository, nodes: any NodeRepository, initialState: OnboardingState = OnboardingState(), created: @escaping (AccountRecord) -> Void = { _ in }, restoreBackup: @escaping () -> Void = {},
                forget: @escaping (String) -> Void = { _ in }, completion: @escaping (AccountRecord?) -> Void) {
        self.repository = repository; self.nodes = nodes; self.initialState = initialState; self.created = created; self.restoreBackup = restoreBackup; self.forget = forget; self.completion = completion
    }
    public func send(_ action: OnboardingAction) { viewModel.send(action) }
}
