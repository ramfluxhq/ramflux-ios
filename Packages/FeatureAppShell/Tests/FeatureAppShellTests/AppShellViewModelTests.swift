// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureAppShell

private actor SessionFake: SessionRepository {
    private let pair = AsyncStream<SessionSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var blocked: CheckedContinuation<RepositoryResult<SessionSnapshot>, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var activated = false
    private let delay: Bool
    private(set) var selected: [String] = []
    private(set) var suspensions = 0
    init(delay: Bool = false) { self.delay = delay }
    func snapshots() -> AsyncStream<SessionSnapshot> { pair.stream }
    func activate() async -> RepositoryResult<SessionSnapshot> {
        if delay {
            return await withCheckedContinuation { blocked = $0; activated = true; entered?.resume(); entered = nil }
        }
        let value = Self.ready
        pair.continuation.yield(value)
        return .success(value)
    }
    func waitForActivation() async {
        if activated { return }
        await withCheckedContinuation { entered = $0 }
    }
    func releaseActivation() { blocked?.resume(returning: .success(Self.ready)); blocked = nil }
    func suspend() -> RepositoryResult<Void> { suspensions += 1; return .success(()) }
    func selectAccount(_ id: String) -> RepositoryResult<SessionSnapshot> { selected.append(id); return .success(Self.ready) }
    static var ready: SessionSnapshot { SessionSnapshot(phase: .ready, accounts: [AccountRecord(id: "a", displayName: "Account", isLocked: false)], activeAccountID: "a") }
    deinit { pair.continuation.finish() }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct AppShellViewModelTests {
    @Test func unavailableIsTypedAndNeverInventsAnAccount() async {
        let model = AppShellViewModel(repository: UnavailableSessionRepository(), emit: { _ in })
        model.send(.appeared); await model.settle()
        #expect(model.state.session.phase == .unavailable(.nativeCoreMissing))
        #expect(model.state.session.accounts.isEmpty)
        #expect(!model.state.privacyShield)
        model.send(.disappeared); await model.settle()
    }
    @Test func inactiveImmediatelyConcealsRecordsAndFencesLateCompletion() async {
        let repository = SessionFake(delay: true)
        var events: [AppShellEvent] = []
        let model = AppShellViewModel(repository: repository, emit: { events.append($0) })
        model.send(.appeared)
        await repository.waitForActivation()
        model.send(.sceneInactive)
        await repository.releaseActivation(); await model.settle()
        #expect(model.state.privacyShield)
        #expect(model.state.session.accounts.isEmpty)
        #expect(events == [.dismissPrivateNavigation])
        model.send(.sceneBackground); await model.settle()
        #expect(await repository.suspensions == 1)
        model.send(.disappeared); await model.settle()
    }
    @Test func navigationEventsAreOneShotAndLinksCannotApprove() async throws {
        var events: [AppShellEvent] = []
        let model = AppShellViewModel(repository: SessionFake(), emit: { events.append($0) })
        model.send(.appeared); await model.settle()
        model.send(.deepLink(try #require(URL(string: "ramflux://conversation/thread"))))
        model.send(.deepLink(try #require(URL(string: "ramflux://settings?approve=true"))))
        #expect(events == [.navigate(.conversation("thread"))])
        #expect(model.state.session.activeAccountID == "a")
        model.send(.sceneInactive)
        model.send(.deepLink(try #require(URL(string: "ramflux://conversation/other"))))
        #expect(events.last == .dismissPrivateNavigation)
        model.send(.disappeared); await model.settle()
    }
    @Test func unknownAccountCannotReachRepository() async {
        let repository = SessionFake()
        let model = AppShellViewModel(repository: repository, emit: { _ in })
        model.send(.appeared); await model.settle()
        model.send(.selectAccount("untrusted")); await model.settle()
        #expect(await repository.selected.isEmpty)
        model.send(.selectAccount("a")); await model.settle()
        #expect(await repository.selected == ["a"])
        model.send(.disappeared); await model.settle()
    }
    @Test func coordinatorOwnsNavigationAndClearsItOnBackground() async {
        let coordinator = AppShellCoordinator(repository: SessionFake())
        coordinator.send(.appeared); await coordinator.viewModel.settle()
        coordinator.send(.open(.settings)); coordinator.send(.openAccounts)
        #expect(coordinator.path == [.settings]); #expect(coordinator.sheet == .accounts)
        coordinator.send(.sceneInactive)
        #expect(coordinator.path.isEmpty); #expect(coordinator.sheet == nil)
        coordinator.send(.disappeared); await coordinator.viewModel.settle()
    }
    @Test func immutableStateAndAllPreviewStatesAreDistinct() {
        #expect(Set(AppShellPreviews.cases.map(\.id)).count == 6)
        let before = AppShellState()
        var after = before; after.tab = .agents
        #expect(before.tab == .messages); #expect(before != after)
    }
}
