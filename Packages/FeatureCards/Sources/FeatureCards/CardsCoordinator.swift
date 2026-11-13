// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class CardsCoordinator {
    public let viewModel: CardsViewModel
    public init(repository: any CardsRepository) { viewModel = CardsViewModel(repository: repository) }
    public func send(_ action: CardsAction) { viewModel.send(action) }
}
