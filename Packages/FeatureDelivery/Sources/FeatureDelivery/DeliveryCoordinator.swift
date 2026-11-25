// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class DeliveryCoordinator {
    public let viewModel: DeliveryViewModel
    public init(repository: any DeliveryRepository, account: @escaping @MainActor () -> String?) { viewModel = DeliveryViewModel(repository: repository, account: account) }
    public func send(_ action: DeliveryAction) { viewModel.send(action) }
}
