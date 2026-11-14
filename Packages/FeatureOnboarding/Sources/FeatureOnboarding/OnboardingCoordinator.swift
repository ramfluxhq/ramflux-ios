// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
@Observable @MainActor public final class OnboardingCoordinator {
    public let secureSlot = SecureRecoverySlot()
    private let repository: any OnboardingRepository
    private let nodes: any NodeRepository
    private let completion: (AccountRecord?) -> Void
    private let created: () -> Void
    @ObservationIgnored public lazy var viewModel = OnboardingViewModel(repository: repository, nodes: nodes) { [weak self] event in
        switch event { case .accountCreated(let account): self?.completion(account); self?.created(); case .completed(let account): self?.completion(account); case .dismissed: self?.completion(nil); case .presentRecovery(let id, let display): self?.secureSlot.install(id: id, display: display); case .revokeRecovery: self?.secureSlot.revoke() }
    }
    public init(repository: any OnboardingRepository, nodes: any NodeRepository, created: @escaping () -> Void = {}, completion: @escaping (AccountRecord?) -> Void) {
        self.repository = repository; self.nodes = nodes; self.created = created; self.completion = completion
    }
    public func send(_ action: OnboardingAction) { viewModel.send(action) }
}
