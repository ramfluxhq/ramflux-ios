// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
@MainActor public final class PermissionsCoordinator {
    public let viewModel: PermissionsViewModel
    public init(repository: any DevicePermissionsRepository, emit: @escaping @MainActor (PermissionsEvent) -> Void = { _ in }) { viewModel = PermissionsViewModel(repository: repository, emit: emit) }
    public func send(_ action: PermissionsAction) { viewModel.send(action) }
}
