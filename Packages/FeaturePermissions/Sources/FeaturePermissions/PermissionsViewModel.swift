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
    @ObservationIgnored private var registrationNeeded = false
    @ObservationIgnored private var sceneActive = false
    @ObservationIgnored private var sceneGeneration: UInt64 = 0
    @ObservationIgnored private var settingsPending: DeviceSettingsDestination?
    @ObservationIgnored private var offerPending: String?
    @ObservationIgnored private var notificationOfferAccount: String?
    public init(repository: any DevicePermissionsRepository, emit: @escaping @MainActor (PermissionsEvent) -> Void = { _ in }) { self.repository = repository; self.emit = emit }
    public func send(_ action: PermissionsAction) {
        switch action {
        case .appeared: refresh()
        case .foreground: sceneGeneration &+= 1; sceneActive = true; refresh(register: true)
        case .sceneInactive: sceneActive = false
        case .disappeared: break // App-scoped coordinator owns an in-flight system prompt across navigation.
        case .accountCreated(let accountID):
            offerPending = accountID; offerIfIdle()
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
            if let accountID = notificationOfferAccount {
                repository.consumeNotificationOffer(accountID: accountID); notificationOfferAccount = nil
            }
            guard let permission = pending else { offerIfIdle(); return }; pending = nil
            run { [repository] in
                let result = await repository.request(permission)
                if permission == .notifications { await repository.registerForNotificationsIfAuthorized() }
                let snapshot = await repository.snapshot()
                return .requested(permission, result, snapshot)
            }
        case .openSettings:
            guard !state.busy else { return }
            settingsPending = state.permissionNeeded == .notifications ? .notifications : .app
            openSettingsIfReady()
        case .dismissNeeded: state.permissionNeeded = nil; settingsPending = nil
        }
    }
    private func openSettingsIfReady() {
        guard sceneActive, !state.busy, let destination = settingsPending else { return }
        let activation = sceneGeneration
        run { [repository] in .settings(await repository.openSettings(destination: destination), activation) }
    }
    private func offerIfIdle() {
        guard let accountID = offerPending, !state.busy, state.explanation == nil, state.permissionNeeded == nil, pending == nil, notificationOfferAccount == nil else { return }
        offerPending = nil
        if !repository.notificationOfferConsumed(accountID: accountID) {
            notificationOfferAccount = accountID; need(.notifications)
        }
    }
    private func install(_ snapshot: DevicePermissionsSnapshot) {
        state.snapshot = snapshot
        if let needed = state.permissionNeeded, needed.isUsable(snapshot[needed]) { state.permissionNeeded = nil }
    }
    private func need(_ permission: DevicePermission) {
        guard !state.busy, state.explanation == nil else { return }
        guard [.notifications, .camera, .photoAdd].contains(permission) else { state.failure = .unsupported; return }
        if state.permissionNeeded != permission { settingsPending = nil }
        state.permissionNeeded = nil
        run { [repository] in .needed(permission, await repository.snapshot()) }
    }
    private func refresh(register: Bool = false) {
        guard !state.busy else { refreshNeeded = true; registrationNeeded = registrationNeeded || register; return }
        run { [repository] in
            if register { await repository.registerForNotificationsIfAuthorized() }
            return .snapshot(await repository.snapshot())
        }
    }
    private enum Completion {
        case snapshot(DevicePermissionsSnapshot), needed(DevicePermission, DevicePermissionsSnapshot)
        case requested(DevicePermission, RepositoryResult<DevicePermissionStatus>, DevicePermissionsSnapshot), settings(DeviceSettingsOpenResult, UInt64)
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
                if permission == .notifications, self.state.explanation == nil { self.notificationOfferAccount = nil }
            case .requested(let permission, let result, let value):
                self.install(value)
                switch result {
                case .success(let status) where permission.isUsable(status): self.emit(.ready(permission))
                case .success: self.state.permissionNeeded = permission
                case .failure(let failure): self.state.failure = failure
                }
            case .settings(let result, let activation):
                switch result {
                case .opened: self.settingsPending = nil
                case .failed: self.settingsPending = nil; self.state.failure = .localFailure
                case .deferred: if activation == self.sceneGeneration { self.sceneActive = false }
                }
            }
            if self.offerPending != nil { self.offerIfIdle() }
            if !self.state.busy, self.refreshNeeded {
                let register = self.registrationNeeded
                self.refreshNeeded = false; self.registrationNeeded = false; self.refresh(register: register)
            }
            self.openSettingsIfReady()
        }
    }
    public func settle() async { while true { let id = generation; await work?.value; if id == generation { return } } }
    deinit { work?.cancel() }
}
