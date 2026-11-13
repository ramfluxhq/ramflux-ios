// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData
@Observable @MainActor public final class CardsViewModel {
    public private(set) var state = CardsState()
    private let repository: any CardsRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    public init(repository: any CardsRepository) { self.repository = repository }
    public func send(_ action: CardsAction) {
        generation &+= 1; task?.cancel()
        guard action != .disappeared else { state = CardsState(); return }
        state.checking = true; let current = generation
        task = Task { [weak self, repository] in
            let result = await repository.availability()
            guard !Task.isCancelled, let self, self.generation == current else { return }; self.state.checking = false
            switch result { case .failure(let failure): self.state.failure = failure; case .success: self.state.failure = .invalidData }
        }
    }
    public func settle() async { await task?.value }
    deinit { task?.cancel() }
}
