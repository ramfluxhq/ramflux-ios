// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
import FeatureAppShell

/// Platform execution lease; feature UI remains synchronous and emits only Actions.
@MainActor final class AppLifecycleCoordinator {
    private var lease: UIBackgroundTaskIdentifier = .invalid
    private var completion: Task<Void, Never>?
    func enterBackground(_ coordinator: AppShellCoordinator) {
        guard lease == .invalid else { return }
        lease = UIApplication.shared.beginBackgroundTask(withName: RamfluxAppStrings.text("copy.94e3068f8e98")) { [weak self] in self?.endLease() }
        coordinator.send(.sceneBackground)
        completion?.cancel()
        completion = Task { [weak self, model = coordinator.viewModel] in
            await model.settle()
            self?.endLease()
        }
    }
    private func endLease() {
        let current = lease; lease = .invalid
        if current != .invalid { UIApplication.shared.endBackgroundTask(current) }
        // Expiration never reports writer release and never cancels native cleanup.
    }
    deinit { completion?.cancel() }
}
