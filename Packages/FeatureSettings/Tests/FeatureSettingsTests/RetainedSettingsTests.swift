// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureSettings
private actor RetainedSettingsFake: SettingsRepository {
    let journal = RetainedMutation<SettingsMutation, Void>()
    let gate: SettingsGate
    private(set) var attempts: [PendingSettingsMutation] = []
    init(gate: SettingsGate) { self.gate = gate }
    func pending(account: String?) async -> PendingSettingsMutation? { guard let entry = await journal.snapshot(scope: account ?? "device"), entry.unresolved else { return nil }; return PendingSettingsMutation(change: entry.arguments, operationID: entry.operationID) }
    func mutate(account: String?, change: SettingsMutation, operationID: String) async -> RepositoryResult<Void> { await journal.run(scope: account ?? "device", arguments: change, operationID: operationID) { await self.perform(change, operationID) } }
    func perform(_ change: SettingsMutation, _ key: String) async -> RepositoryResult<Void> { attempts.append(PendingSettingsMutation(change: change, operationID: key)); await gate.wait(); return .failure(.outcomeUnknown) }
    func snapshot(account: String?) -> RepositoryResult<SettingsSnapshot> { .success(SettingsSnapshot(accountID: account, devices: [DeviceRecord(id: "peer", isLocal: false, capabilities: [])])) }
    func revoke(account: String, device: DeviceRecord, operationID: String) async -> RepositoryResult<Void> { await mutate(account: account, change: .revoke(device), operationID: operationID) }
    func lock(account: String) -> RepositoryResult<Void> { .failure(.unsupported) }
    func retention(account: String, seconds: Int64, operationID: String) -> RepositoryResult<Void> { .failure(.unsupported) }
    func requireManualRequests(account: String, operationID: String) -> RepositoryResult<Void> { .failure(.unsupported) }
    nonisolated func unavailable(_ capability: SettingsUnavailable) -> AppFailure { .unsupported }
    func observe(account: String) -> RepositoryObservation { let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated); return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() }) }
}
private actor SettingsGate {
    nonisolated let entered = AsyncStream<Void>.makeStream()
    nonisolated let released = AsyncStream<Void>.makeStream()
    func wait() async { entered.continuation.yield(()); var iterator = released.stream.makeAsyncIterator(); _ = await iterator.next() }
    nonisolated func release() { released.continuation.yield(()); released.continuation.finish() }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct RetainedSettingsTests {
    @Test func cancelledWaiterAndRouteReplacementKeepOriginalConfigurationKey() async {
        let gate = SettingsGate(), repository = RetainedSettingsFake(gate: gate); defer { gate.release() }
        let preferences = NativePreferencesRepository(suite: "retained-settings-" + UUID().uuidString)
        @MainActor func model(_ route: AppRoute) -> SettingsViewModel { SettingsViewModel(repository: repository, backup: UnavailableBackupRepository(), nodes: UnavailableNodeRepository(), preferences: preferences, account: "a", state: SettingsState(route: route), emit: { _ in }) }
        let first = model(.device("peer")); first.send(.refresh); await first.settle(); first.send(.requestRevoke("peer")); first.send(.confirmRevoke("peer"))
        var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next(); first.send(.disappeared); gate.release(); await first.settle()
        let replacement = model(.account); replacement.send(.refresh); await replacement.settle()
        guard let pending = replacement.state.pendingMutation else { Issue.record("Lost repository operation gate"); return }
        replacement.send(.retention(3600)); replacement.send(.saveRetention); await replacement.settle(); #expect(await repository.attempts.count == 1)
        replacement.send(.reconcileOriginal("wrong")); await replacement.settle(); #expect(await repository.attempts.count == 1)
        replacement.send(.reconcileOriginal(pending.operationID)); await replacement.settle(); #expect(await repository.attempts.count == 2); #expect((await repository.attempts).allSatisfy { $0 == pending }); replacement.send(.disappeared)
    }
}
