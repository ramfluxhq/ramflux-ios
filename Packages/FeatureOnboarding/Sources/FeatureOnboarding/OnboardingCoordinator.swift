// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
@Observable @MainActor public final class OnboardingCoordinator {
    private let repository: any OnboardingRepository
    private let nodes: any NodeRepository
    private let completion: (AccountRecord?) -> Void
    @ObservationIgnored public lazy var viewModel = OnboardingViewModel(repository: repository, nodes: nodes) { [weak self] event in
        switch event { case .completed(let account): self?.completion(account); case .dismissed: self?.completion(nil) }
    }
    public init(repository: any OnboardingRepository, nodes: any NodeRepository, completion: @escaping (AccountRecord?) -> Void) {
        self.repository = repository; self.nodes = nodes; self.completion = completion
    }
    public func send(_ action: OnboardingAction) { viewModel.send(action) }
}
