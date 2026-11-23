// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureSettings

private actor SettingsFake: SettingsRepository {
    private(set) var revoked: [String] = []
    let unknown: Bool
    init(unknown: Bool = false) { self.unknown = unknown }
    func snapshot(account: String?) -> RepositoryResult<SettingsSnapshot> { .success(SettingsSnapshot(accountID: account)) }
    func revoke(account: String, device: DeviceRecord, operationID: String) -> RepositoryResult<Void> { revoked.append(device.id); return unknown ? .failure(.outcomeUnknown) : .success(()) }
    func lock(account: String) -> RepositoryResult<Void> { .success(()) }
    func retention(account: String, seconds: Int64, operationID: String) -> RepositoryResult<Void> { .success(()) }
    func requireManualRequests(account: String, operationID: String) -> RepositoryResult<Void> { .success(()) }
    func observe(account: String) -> RepositoryObservation { RepositoryObservation(stream: AsyncStream { $0.finish() }) }
    nonisolated func unavailable(_ capability: SettingsUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct SettingsViewModelTests {
    private func model(_ repository: SettingsFake, state: SettingsState = SettingsState()) -> SettingsViewModel {
        SettingsViewModel(repository: repository, nodes: UnavailableNodeRepository(), preferences: NativePreferencesRepository(suite: "settings-tests-" + UUID().uuidString), account: "account", state: state, emit: { _ in })
    }
    @Test func revocationRequiresSelectedNonlocalDeviceAndExactConfirmation() async {
        let fake = SettingsFake(); var state = SettingsState()
        state.snapshot = SettingsSnapshot(devices: [DeviceRecord(id: "local", isLocal: true, capabilities: []), DeviceRecord(id: "peer", isLocal: false, capabilities: [])])
        let vm = model(fake, state: state)
        vm.send(.requestRevoke("local")); #expect(vm.state.pendingRevoke == nil)
        vm.send(.confirmRevoke("peer")); await vm.settle(); #expect(await fake.revoked.isEmpty)
        vm.send(.requestRevoke("peer")); vm.send(.confirmRevoke("other")); await vm.settle(); #expect(await fake.revoked.isEmpty)
        vm.send(.confirmRevoke("peer")); await vm.settle(); #expect(await fake.revoked == ["peer"])
        vm.send(.disappeared); #expect(vm.state.pendingRevoke == nil)
    }
    @Test func unknownMutationSurvivesConcealmentAndPreventsAnotherRevocation() async {
        let fake = SettingsFake(unknown: true); var state = SettingsState()
        state.snapshot = SettingsSnapshot(devices: [DeviceRecord(id: "peer", isLocal: false, capabilities: [])])
        let vm = model(fake, state: state)
        vm.send(.requestRevoke("peer")); vm.send(.confirmRevoke("peer")); await vm.settle()
        #expect(vm.state.unknownMutation); vm.send(.confirmRevoke("peer")); await vm.settle()
        #expect(await fake.revoked == ["peer"]); vm.send(.disappeared); #expect(vm.state.unknownMutation)
    }
    @Test func unavailableSettingsNeverInventDevices() async {
        let vm = SettingsViewModel(repository: UnavailableSettingsRepository(), nodes: UnavailableNodeRepository(), preferences: NativePreferencesRepository(suite: "settings-tests-" + UUID().uuidString), account: "account", state: SettingsState(route: .devices), emit: { _ in })
        vm.send(.refresh); await vm.settle()
        #expect(vm.state.failure == .sdkUnavailable); #expect(vm.state.snapshot.devices.isEmpty); vm.send(.disappeared)
    }
}
