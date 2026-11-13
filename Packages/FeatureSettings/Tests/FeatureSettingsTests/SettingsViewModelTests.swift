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
private actor BackupFake: BackupRepository {
    private(set) var installs: [BackupRecord] = []
    func jobs(account: String) -> RepositoryResult<[BackupRecord]> { .success([]) }
    func create(account: String, credentials: SensitiveSubmission, operationID: String) -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.unsupported) }
    func verify(account: String, source: URL, credentials: SensitiveSubmission, operationID: String) -> RepositoryResult<BackupRecord> { credentials.erase(); return .failure(.unsupported) }
    func install(account: String, expected: BackupRecord, credentials: SensitiveSubmission, operationID: String) -> RepositoryResult<BackupRecord> { credentials.erase(); installs.append(expected); return .success(expected) }
    func cancel(account: String, jobID: String, operationID: String) -> RepositoryResult<Void> { .success(()) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct SettingsViewModelTests {
    private func model(_ repository: SettingsFake, backup: BackupFake = BackupFake(), state: SettingsState = SettingsState()) -> SettingsViewModel {
        SettingsViewModel(repository: repository, backup: backup, nodes: UnavailableNodeRepository(), preferences: NativePreferencesRepository(suite: "settings-tests-" + UUID().uuidString), account: "account", state: state, emit: { _ in })
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
    @Test func mobileBackupActionsCannotCreateImportInstallOrRevealAForm() async {
        let fake = BackupFake(), job = BackupRecord(id: "job", kind: "restore", state: "verified", sequence: 7, accountID: "archive")
        var state = SettingsState(route: .backup); state.jobs = [job]; state.attended = true
        let vm = model(SettingsFake(), backup: fake, state: state)
        vm.send(.createBackup); vm.send(.selectImport); vm.send(.requestInstall("job")); vm.send(.restoreHold("job", 7))
        vm.send(.submitBackup(SensitiveSubmission(values: ["passphrase": "test"]))); await vm.settle()
        #expect(await fake.installs.isEmpty); #expect(vm.state.backupIntent == nil); #expect(!vm.state.importSelecting); #expect(!vm.state.restoreHeld); #expect(vm.state.failure == .unsupported); vm.send(.disappeared)
    }
    @Test func unavailableSettingsNeverInventDevicesOrCompletedBackups() async {
        let vm = SettingsViewModel(repository: UnavailableSettingsRepository(), backup: UnavailableBackupRepository(), nodes: UnavailableNodeRepository(), preferences: NativePreferencesRepository(suite: "settings-tests-" + UUID().uuidString), account: "account", state: SettingsState(route: .backup), emit: { _ in })
        vm.send(.refresh); await vm.settle()
        #expect(vm.state.failure == .sdkUnavailable); #expect(vm.state.jobs.isEmpty); #expect(vm.state.snapshot.devices.isEmpty)
        vm.send(.createBackup); #expect(vm.state.backupIntent == nil); vm.send(.disappeared)
    }
}
