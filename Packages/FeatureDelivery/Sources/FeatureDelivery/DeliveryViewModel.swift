// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Observation
import AppData

@MainActor @Observable public final class DeliveryViewModel {
    public private(set) var state = DeliveryState()
    @ObservationIgnored private let repository: any DeliveryRepository
    @ObservationIgnored private let account: @MainActor () -> String?
    @ObservationIgnored private var task: Task<Void, Never>?
    public init(repository: any DeliveryRepository, account: @escaping @MainActor () -> String?) { self.repository = repository; self.account = account }
    public func send(_ action: DeliveryAction) {
        switch action {
        case .appeared, .foreground: reload()
        case .selfTest:
            Task { [repository] in let sent = await repository.scheduleSelfTest(); state.selfTest = sent ? .sent : .failed }
        }
    }
    /// Re-reads every signal; the page shows the answer when the user returns from Settings.
    public func settle() async { await task?.value }
    private func reload() {
        task?.cancel()
        let account = account()
        task = Task { [repository] in
            let snapshot = await repository.snapshot(account: account)
            guard !Task.isCancelled else { return }
            state.snapshot = snapshot
        }
    }
}
