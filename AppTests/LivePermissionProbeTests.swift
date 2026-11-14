// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import SwiftUI
import UIKit
import AppData
import FeaturePermissions
import RFDesign
/// Recording decorator over the real OS repository; it does not manufacture permission results.
@MainActor private final class LivePermissionProbeRepository: DevicePermissionsRepository {
    let native: NativeDevicePermissionsRepository
    let decisions = AsyncStream<RepositoryResult<DevicePermissionStatus>>.makeStream(bufferingPolicy: .bufferingNewest(1))
    init(defaults: UserDefaults) { native = NativeDevicePermissionsRepository(defaults: defaults) }
    func snapshot() async -> DevicePermissionsSnapshot { await native.snapshot() }
    func claimNotificationOffer() -> Bool { native.claimNotificationOffer() }
    func request(_ permission: DevicePermission) async -> RepositoryResult<DevicePermissionStatus> {
        let result = await native.request(permission); decisions.continuation.yield(result); return result
    }
    func openSettings() async -> Bool { await native.openSettings() }
}
@MainActor final class LivePermissionProbeTests: XCTestCase {
    func testOptInExplanationSystemPromptAndRealStatus() async throws {
        // Opt in via simulator defaults for this app; ordinary CI never interrupts snapshots with OS prompts.
        guard let name = UserDefaults.standard.string(forKey: "RFPermissionProbe"), let permission = DevicePermission(rawValue: name), [.notifications, .camera, .photoAdd].contains(permission) else { throw XCTSkip("Opt-in real OS permission probe") }
        let suite = "live-permission-probe-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let repository = LivePermissionProbeRepository(defaults: defaults)
        let initial = await repository.snapshot()
        guard initial[permission] == .notAsked else { throw XCTSkip("Probe requires not-determined OS authorization") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let coordinator = PermissionsCoordinator(repository: repository)
        let hosting = UIHostingController(rootView: RFThemeScope {
            PermissionsHost(coordinator: coordinator)
                .background(PermissionsPresentationHost(coordinator: coordinator))
        }.environment(\.scenePhase, .active))
        window.rootViewController = hosting; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        hosting.view.layoutIfNeeded()
        await coordinator.viewModel.settle()
        coordinator.send(permission == .notifications ? .accountCreated : .need(permission))
        await coordinator.viewModel.settle()
        XCTAssertEqual(coordinator.viewModel.state.explanation, permission)
        let timeout = Task { do { try await Task.sleep(for: .seconds(90)) } catch { return }; repository.decisions.continuation.finish() }
        var results = repository.decisions.stream.makeAsyncIterator()
        let result = await results.next()
        timeout.cancel(); await timeout.value
        let decision = try XCTUnwrap(result, "Permission UI probe exceeded its deadline")
        await coordinator.viewModel.settle()
        guard case .success(let status) = decision else { XCTFail("Real system permission request failed"); return }
        XCTAssertNotEqual(status, .notAsked)
        let snapshot = await repository.snapshot()
        XCTAssertEqual(coordinator.viewModel.state.snapshot[permission], snapshot[permission])
        XCTAssertEqual(status, snapshot[permission])
        if status == .denied { XCTAssertEqual(coordinator.viewModel.state.permissionNeeded, permission) }
    }
}
