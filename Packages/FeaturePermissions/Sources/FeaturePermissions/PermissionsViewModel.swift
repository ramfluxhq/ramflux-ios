// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
import Observation
@Observable @MainActor public final class PermissionsViewModel {
    public private(set) var state = PermissionsState()
    private let repository: any DevicePermissionsRepository
    private let emit: @MainActor (PermissionsEvent) -> Void
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var pending: DevicePermission?
    @ObservationIgnored private var refreshNeeded = false
    @ObservationIgnored private var offerPending = false
    public init(repository: any DevicePermissionsRepository, emit: @escaping @MainActor (PermissionsEvent) -> Void = { _ in }) { self.repository = repository; self.emit = emit }
    public func send(_ action: PermissionsAction) {
        switch action {
        case .appeared, .foreground: refresh()
        case .disappeared: break // App-scoped coordinator owns an in-flight system prompt across navigation.
        case .accountCreated:
            offerPending = true; offerIfIdle()
        case .need(let permission):
            guard permission != .notifications else { return } // Notifications have one post-creation offer only.
            need(permission)
        case .confirmExplanation:
            guard !state.busy, let permission = state.explanation else { return }
            pending = permission; state.explanation = nil; state.busy = true
        case .cancelExplanation:
            guard state.explanation != nil else { return }
            pending = nil; state.explanation = nil
        case .explanationDismissed:
            guard let permission = pending else { offerIfIdle(); return }; pending = nil
            run { [repository] in
                let result = await repository.request(permission), snapshot = await repository.snapshot()
                return .requested(permission, result, snapshot)
            }
        case .openSettings:
            guard !state.busy else { return }
            run { [repository] in .settings(await repository.openSettings()) }
        case .dismissNeeded: state.permissionNeeded = nil
        }
    }
    private func offerIfIdle() {
        guard offerPending, !state.busy, state.explanation == nil, state.permissionNeeded == nil, pending == nil else { return }
        offerPending = false
        if repository.claimNotificationOffer() { need(.notifications) }
    }
    private func install(_ snapshot: DevicePermissionsSnapshot) {
        state.snapshot = snapshot
        if let needed = state.permissionNeeded, needed.isUsable(snapshot[needed]) { state.permissionNeeded = nil }
    }
    private func need(_ permission: DevicePermission) {
        guard !state.busy, state.explanation == nil else { return }
        guard [.notifications, .camera, .photoAdd].contains(permission) else { state.failure = .unsupported; return }
        state.permissionNeeded = nil
        run { [repository] in .needed(permission, await repository.snapshot()) }
    }
    private func refresh() {
        guard !state.busy else { refreshNeeded = true; return }
        run { [repository] in .snapshot(await repository.snapshot()) }
    }
    private enum Completion {
        case snapshot(DevicePermissionsSnapshot), needed(DevicePermission, DevicePermissionsSnapshot)
        case requested(DevicePermission, RepositoryResult<DevicePermissionStatus>, DevicePermissionsSnapshot), settings(Bool)
    }
    private func run(_ operation: @escaping @MainActor () async -> Completion) {
        generation &+= 1; let id = generation; work?.cancel(); state.busy = true; state.failure = nil
        work = Task { [weak self] in
            let result = await operation()
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.state.busy = false
            switch result {
            case .snapshot(let value): self.install(value)
            case .needed(let permission, let value):
                self.install(value)
                if permission.isUsable(value[permission]) { self.emit(.ready(permission)) }
                else if value[permission] == .notAsked { self.state.explanation = permission }
                else { self.state.permissionNeeded = permission }
            case .requested(let permission, let result, let value):
                self.install(value)
                switch result {
                case .success(let status) where permission.isUsable(status): self.emit(.ready(permission))
                case .success: self.state.permissionNeeded = permission
                case .failure(let failure): self.state.failure = failure
                }
            case .settings(let opened): if !opened { self.state.failure = .localFailure }
            }
            if self.offerPending { self.offerIfIdle() }
            if !self.state.busy, self.refreshNeeded { self.refreshNeeded = false; self.refresh() }
        }
    }
    public func settle() async { while true { let id = generation; await work?.value; if id == generation { return } } }
    deinit { work?.cancel() }
}
