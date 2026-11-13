// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
#if os(iOS)
import UIKit
#endif
@MainActor public final class CallsCoordinator {
    public let viewModel: CallsViewModel
    private var settings: Task<Void, Never>?
    public init(repository: any CallsRepository, microphone: any MicrophoneRepository, account: String, mode: CallsMode = .history) {
        let relay = CallsSettingsRelay()
        viewModel = CallsViewModel(repository: repository, microphone: microphone, account: account, state: CallsState(mode: mode)) { relay.handle($0) }
        relay.callback = { [weak self] in self?.openSettings() }
    }
    public func send(_ action: CallsAction) { if action == .disappeared { settings?.cancel() }; viewModel.send(action) }
    private func openSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { viewModel.send(.settingsResult(false)); return }
        settings?.cancel()
        settings = Task { [weak self] in
            let opened = await UIApplication.shared.open(url)
            guard !Task.isCancelled else { return }; self?.viewModel.send(.settingsResult(opened))
        }
        #else
        viewModel.send(.settingsResult(false))
        #endif
    }
    deinit { settings?.cancel() }
}
