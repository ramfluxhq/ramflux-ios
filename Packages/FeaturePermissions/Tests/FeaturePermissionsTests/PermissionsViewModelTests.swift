// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeaturePermissions
@MainActor private final class PermissionsFake: DevicePermissionsRepository {
    var value = DevicePermissionsSnapshot(values: [.notifications: .notAsked, .camera: .notAsked, .photoAdd: .notAsked, .microphone: .notAsked])
    var requests: [DevicePermission] = []
    var offers = 0
    var consumed: Set<String> = []
    var registrations = 0
    var next: DevicePermissionStatus = .allowed
    var settingsOpened = 0
    var settingsDestinations: [DeviceSettingsDestination] = []
    var deferSettings = false
    var beforeSettingsReturn: (@MainActor () async -> Void)?
    var canOpen = true
    func snapshot() async -> DevicePermissionsSnapshot { value }
    func notificationOfferConsumed(accountID: String) -> Bool { offers += 1; return consumed.contains(accountID) }
    func consumeNotificationOffer(accountID: String) { consumed.insert(accountID) }
    func registerForNotificationsIfAuthorized() async { registrations += 1 }
    func request(_ permission: DevicePermission) async -> RepositoryResult<DevicePermissionStatus> { requests.append(permission); value.values[permission] = next; return .success(next) }
    func openSettings(destination: DeviceSettingsDestination) async -> DeviceSettingsOpenResult {
        settingsOpened += 1; settingsDestinations.append(destination)
        let result: DeviceSettingsOpenResult = deferSettings ? .deferred : (canOpen ? .opened : .failed)
        await beforeSettingsReturn?()
        return result
    }
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
        vm.send(.foreground); vm.send(.accountCreated("new-account")); await vm.settle()
        #expect(vm.state.explanation == .notifications); #expect(repo.offers == 1); #expect(repo.requests.isEmpty)
    }
    @Test func creationOffersOnceAndCancelNeverShowsSystemPrompt() async {
        let repo = PermissionsFake(), vm = PermissionsViewModel(repository: repo)
        vm.send(.accountCreated("new-account")); await vm.settle(); #expect(vm.state.explanation == .notifications)
        #expect(repo.requests.isEmpty)
        vm.send(.cancelExplanation); vm.send(.explanationDismissed); await vm.settle()
        #expect(repo.requests.isEmpty); #expect(vm.state.explanation == nil)
        vm.send(.accountCreated("new-account")); await vm.settle(); #expect(vm.state.explanation == nil); #expect(repo.requests.isEmpty)
    }
    @Test func interruptedOfferRemainsEligibleAndResolvedOfferIsPerAccount() async {
        let repo = PermissionsFake()
        let interrupted = PermissionsViewModel(repository: repo)
        interrupted.send(.accountCreated("first")); await interrupted.settle()
        #expect(interrupted.state.explanation == .notifications); #expect(repo.consumed.isEmpty)
        let restarted = PermissionsViewModel(repository: repo)
        restarted.send(.accountCreated("first")); await restarted.settle()
        #expect(restarted.state.explanation == .notifications)
        restarted.send(.cancelExplanation); #expect(repo.consumed.isEmpty)
        restarted.send(.explanationDismissed); await restarted.settle()
        #expect(repo.consumed == ["first"]); #expect(repo.requests.isEmpty)
        restarted.send(.accountCreated("second")); await restarted.settle()
        #expect(restarted.state.explanation == .notifications); #expect(!repo.consumed.contains("second"))
        restarted.send(.confirmExplanation); #expect(!repo.consumed.contains("second")); #expect(repo.requests.isEmpty)
        restarted.send(.explanationDismissed); await restarted.settle()
        #expect(repo.consumed == ["first", "second"]); #expect(repo.requests == [.notifications])
        #expect(repo.registrations == 1)
    }
    @Test func readsDoNotRegisterAndForegroundIsExplicit() async {
        let repo = PermissionsFake(), vm = PermissionsViewModel(repository: repo)
        vm.send(.appeared); vm.send(.appeared); await vm.settle(); #expect(repo.registrations == 0)
        vm.send(.appeared); vm.send(.foreground); await vm.settle(); #expect(repo.registrations == 1)
        vm.send(.need(.camera)); await vm.settle()
        vm.send(.confirmExplanation); vm.send(.explanationDismissed); await vm.settle()
        #expect(repo.registrations == 1)
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
        vm.send(.foreground); await vm.settle()
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
    @Test func inactiveSettingsWaitForForegroundAndOpenOnce() async {
        let repo = PermissionsFake(), vm = PermissionsViewModel(repository: repo)
        vm.send(.openSettings); await vm.settle()
        #expect(repo.settingsOpened == 0); #expect(vm.state.failure == nil)
        vm.send(.sceneInactive); vm.send(.foreground); await vm.settle()
        #expect(repo.settingsDestinations == [.app])
        vm.send(.foreground); await vm.settle(); #expect(repo.settingsOpened == 1)
    }
    @Test func unavailableNativeSceneDefersUntilAnotherForeground() async {
        let repo = PermissionsFake(); repo.deferSettings = true
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.foreground); await vm.settle(); vm.send(.openSettings); await vm.settle()
        #expect(repo.settingsOpened == 1); #expect(vm.state.failure == nil)
        vm.send(.appeared); await vm.settle(); #expect(repo.settingsOpened == 1)
        repo.deferSettings = false; vm.send(.foreground); await vm.settle()
        #expect(repo.settingsOpened == 2)
        vm.send(.foreground); await vm.settle(); #expect(repo.settingsOpened == 2)
    }
    @Test func deniedNotificationsUseTheirPublicSettingsDestination() async {
        let repo = PermissionsFake(); repo.value.values[.notifications] = .denied
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.foreground); await vm.settle(); vm.send(.accountCreated("first")); await vm.settle()
        #expect(vm.state.permissionNeeded == .notifications)
        vm.send(.openSettings); await vm.settle()
        #expect(repo.settingsDestinations == [.notifications]); #expect(repo.requests.isEmpty)
    }
    @Test func cancellingDeferredNeededStateCancelsSettingsIntent() async {
        let repo = PermissionsFake(); repo.value.values[.notifications] = .denied
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.accountCreated("first")); await vm.settle()
        vm.send(.openSettings); vm.send(.dismissNeeded); vm.send(.foreground); await vm.settle()
        #expect(repo.settingsOpened == 0); #expect(vm.state.permissionNeeded == nil)
    }
    @Test(arguments: [DevicePermission.notifications, .camera, .photoAdd])
    func replacingPermissionNeedCancelsPendingSettings(original: DevicePermission) async {
        let repo = PermissionsFake()
        for permission: DevicePermission in [.notifications, .camera, .photoAdd] { repo.value.values[permission] = .denied }
        let vm = PermissionsViewModel(repository: repo)
        vm.send(original == .notifications ? .accountCreated("first") : .need(original)); await vm.settle()
        #expect(vm.state.permissionNeeded == original)
        vm.send(.openSettings); await vm.settle(); #expect(repo.settingsOpened == 0)
        let replacement: DevicePermission = original == .camera ? .photoAdd : .camera
        vm.send(.need(replacement)); await vm.settle()
        #expect(vm.state.permissionNeeded == replacement)
        vm.send(.foreground); await vm.settle()
        #expect(repo.settingsDestinations.isEmpty); #expect(repo.requests.isEmpty)
        vm.send(.openSettings); await vm.settle()
        #expect(repo.settingsDestinations == [.app])
        vm.send(.foreground); await vm.settle(); #expect(repo.settingsOpened == 1)
    }
    @Test func samePermissionNeedRetainsExplicitPendingSettingsIntent() async {
        let repo = PermissionsFake(); repo.value.values[.camera] = .denied
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.need(.camera)); await vm.settle(); vm.send(.openSettings)
        vm.send(.need(.camera)); await vm.settle()
        #expect(repo.settingsOpened == 0)
        vm.send(.foreground); await vm.settle()
        #expect(repo.settingsDestinations == [.app]); #expect(repo.requests.isEmpty)
    }
    @Test func foregroundDuringDeferredSettingsAttemptIsNotLost() async {
        let repo = PermissionsFake(); repo.deferSettings = true
        let entered = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
        repo.beforeSettingsReturn = {
            entered.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator(); _ = await iterator.next()
        }
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.foreground); await vm.settle(); vm.send(.openSettings)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        vm.send(.sceneInactive); vm.send(.foreground)
        repo.deferSettings = false; repo.beforeSettingsReturn = nil
        release.continuation.yield(()); await vm.settle()
        #expect(repo.settingsOpened == 2); #expect(vm.state.failure == nil)
        entered.continuation.finish(); release.continuation.finish()
    }
    @Test func failedSettingsLinkIsTyped() async {
        let repo = PermissionsFake(); repo.canOpen = false
        let vm = PermissionsViewModel(repository: repo)
        vm.send(.foreground); await vm.settle()
        vm.send(.openSettings); await vm.settle(); #expect(vm.state.failure == .localFailure)
    }
}
