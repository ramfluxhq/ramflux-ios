// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeaturePermissions
@MainActor private final class PermissionsFake: DevicePermissionsRepository {
    var value = DevicePermissionsSnapshot(values: [.notifications: .notAsked, .camera: .notAsked, .photoAdd: .notAsked, .microphone: .notAsked])
    var requests: [DevicePermission] = []
    var offers = 0
    var next: DevicePermissionStatus = .allowed
    var settingsOpened = 0
    var canOpen = true
    func snapshot() async -> DevicePermissionsSnapshot { value }
    func claimNotificationOffer() -> Bool { offers += 1; return offers == 1 }
    func request(_ permission: DevicePermission) async -> RepositoryResult<DevicePermissionStatus> { requests.append(permission); value.values[permission] = next; return .success(next) }
    func openSettings() async -> Bool { settingsOpened += 1; return canOpen }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct PermissionsViewModelTests {
    @Test func launchAndForegroundNeverRequestOrOfferPermission() async {
        let repo = PermissionsFake(), vm = PermissionsViewModel(repository: repo)
        vm.send(.appeared); await vm.settle(); vm.send(.foreground); await vm.settle()
        #expect(vm.state.snapshot[.notifications] == .notAsked); #expect(repo.requests.isEmpty); #expect(repo.offers == 0)
        vm.send(.need(.notifications)); await vm.settle(); #expect(vm.state.explanation == nil)
    }
    @Test func creationOfferIsNotLostDuringForegroundRefresh() async {
        let repo = PermissionsFake(), vm = PermissionsViewModel(repository: repo)
        vm.send(.foreground); vm.send(.accountCreated); await vm.settle()
        #expect(vm.state.explanation == .notifications); #expect(repo.offers == 1); #expect(repo.requests.isEmpty)
    }
    @Test func creationOffersOnceAndCancelNeverShowsSystemPrompt() async {
        let repo = PermissionsFake(), vm = PermissionsViewModel(repository: repo)
        vm.send(.accountCreated); await vm.settle(); #expect(vm.state.explanation == .notifications)
        #expect(repo.requests.isEmpty)
        vm.send(.cancelExplanation); vm.send(.explanationDismissed); await vm.settle()
        #expect(repo.requests.isEmpty); #expect(vm.state.explanation == nil)
        vm.send(.accountCreated); await vm.settle(); #expect(vm.state.explanation == nil); #expect(repo.requests.isEmpty)
    }
    @Test func promptWaitsForActualSheetDismissalAndCannotBeRepeated() async {
        let repo = PermissionsFake(); var events: [PermissionsEvent] = []
        let vm = PermissionsViewModel(repository: repo, emit: { events.append($0) })
        vm.send(.need(.camera)); await vm.settle(); #expect(vm.state.explanation == .camera)
        vm.send(.confirmExplanation); #expect(vm.state.explanation == nil); #expect(repo.requests.isEmpty)
        vm.send(.foreground); #expect(repo.requests.isEmpty)
        vm.send(.explanationDismissed); await vm.settle()
        #expect(repo.requests == [.camera]); #expect(events == [.ready(.camera)])
        vm.send(.explanationDismissed); vm.send(.confirmExplanation); await vm.settle(); #expect(repo.requests == [.camera])
    }
    @Test func denialNeedsSettingsAndRevocationOrGrantRefreshesOnForeground() async {
        let repo = PermissionsFake(); repo.next = .denied
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.need(.photoAdd)); await vm.settle(); vm.send(.confirmExplanation); vm.send(.explanationDismissed); await vm.settle()
        #expect(vm.state.permissionNeeded == .photoAdd); #expect(vm.state.snapshot[.photoAdd] == .denied)
        vm.send(.need(.photoAdd)); await vm.settle(); #expect(vm.state.explanation == nil); #expect(repo.requests == [.photoAdd])
        vm.send(.openSettings); await vm.settle(); #expect(repo.settingsOpened == 1)
        repo.value.values[.photoAdd] = .allowed; vm.send(.foreground); await vm.settle()
        #expect(vm.state.permissionNeeded == nil); #expect(vm.state.snapshot[.photoAdd] == .allowed)
        repo.value.values[.photoAdd] = .denied; vm.send(.foreground); await vm.settle(); #expect(vm.state.snapshot[.photoAdd] == .denied)
    }
    @Test func limitedGrantIsUsableAndUnavailableFeaturesNeverRequest() async {
        let repo = PermissionsFake(); repo.next = .limited; var events: [PermissionsEvent] = []
        let vm = PermissionsViewModel(repository: repo, emit: { events.append($0) })
        vm.send(.need(.photoAdd)); await vm.settle(); vm.send(.confirmExplanation); vm.send(.explanationDismissed); await vm.settle()
        #expect(events == [.ready(.photoAdd)]); #expect(vm.state.snapshot[.photoAdd] == .limited)
        for permission: DevicePermission in [.microphone, .incomingCalls, .files, .photoPicker] {
            vm.send(.need(permission)); await vm.settle(); #expect(vm.state.failure == .unsupported)
        }
        #expect(repo.requests == [.photoAdd])
    }
    @Test func systemRestrictedSensorsAreNeverTreatedAsUsableOrPromptedAgain() async {
        let repo = PermissionsFake(); repo.value.values[.camera] = .restricted; repo.value.values[.photoAdd] = .restricted
        var events: [PermissionsEvent] = []
        let vm = PermissionsViewModel(repository: repo, emit: { events.append($0) })
        for permission: DevicePermission in [.camera, .photoAdd] {
            vm.send(.need(permission)); await vm.settle()
            #expect(vm.state.permissionNeeded == permission); #expect(vm.state.explanation == nil)
        }
        #expect(repo.requests.isEmpty); #expect(events.isEmpty)
    }
    @Test func failedSettingsLinkIsTyped() async {
        let repo = PermissionsFake(); repo.canOpen = false
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.openSettings); await vm.settle(); #expect(vm.state.failure == .localFailure)
    }
}
