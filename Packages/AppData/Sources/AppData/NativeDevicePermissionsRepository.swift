// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
#if os(iOS)
import UIKit
import UserNotifications
import AVFoundation
import Photos
#endif
@MainActor public final class NativeDevicePermissionsRepository: DevicePermissionsRepository {
    private let defaults: UserDefaults
    private var registrationRequested = false
    #if os(iOS)
    private let settingsOpener = NativeDeviceSettingsOpener()
    private var registerNotification: @MainActor () -> Void = { UIApplication.shared.registerForRemoteNotifications() }
    init(defaults: UserDefaults, registerNotification: @escaping @MainActor () -> Void) {
        self.defaults = defaults; self.registerNotification = registerNotification
    }
    #endif
    private static let offerKey = "device.notifications.explanation.v2."
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func notificationOfferConsumed(accountID: String) -> Bool {
        defaults.bool(forKey: Self.offerKey + accountID)
    }
    public func consumeNotificationOffer(accountID: String) {
        defaults.set(true, forKey: Self.offerKey + accountID)
    }
    public func registerForNotificationsIfAuthorized() async {
        #if os(iOS)
        let status = Self.notificationStatus(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        registerIfAllowed(status)
        #endif
    }
    public func snapshot() async -> DevicePermissionsSnapshot {
        #if os(iOS)
        let notifications = Self.notificationStatus(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        let microphone: DevicePermissionStatus = switch AVAudioApplication.shared.recordPermission {
        case .undetermined: .notAsked
        case .denied: .denied
        case .granted: .allowed
        @unknown default: .unavailable
        }
        let background: DevicePermissionStatus = switch UIApplication.shared.backgroundRefreshStatus {
        case .available: .allowed
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unavailable
        }
        return DevicePermissionsSnapshot(values: [.notifications: notifications, .microphone: microphone,
            .camera: Self.cameraStatus(AVCaptureDevice.authorizationStatus(for: .video)),
            .photoAdd: Self.photoStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly)),
            .incomingCalls: .unavailable, .photoPicker: .notRequired, .files: .notRequired, .background: background])
        #else
        return DevicePermissionsSnapshot(values: [.photoPicker: .notRequired, .files: .notRequired])
        #endif
    }
    public func request(_ permission: DevicePermission) async -> RepositoryResult<DevicePermissionStatus> {
        #if os(iOS)
        // Media is unavailable in v1; do not ask for a microphone merely to enable no action.
        guard [.notifications, .camera, .photoAdd].contains(permission) else { return .failure(.unsupported) }
        let current = await snapshot()[permission]
        guard current == .notAsked else { return .success(current) }
        switch permission {
        case .notifications:
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                let result = Self.notificationStatus(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
                return .success(result)
            } catch { return .failure(.localFailure) }
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return .success(Self.cameraStatus(AVCaptureDevice.authorizationStatus(for: .video)))
        case .photoAdd:
            return .success(Self.photoStatus(await PHPhotoLibrary.requestAuthorization(for: .addOnly)))
        default: return .failure(.unsupported)
        }
        #else
        return .failure(.sdkUnavailable)
        #endif
    }
    public func openSettings(destination: DeviceSettingsDestination) async -> DeviceSettingsOpenResult {
        #if os(iOS)
        return await settingsOpener.open(destination)
        #else
        return .failed
        #endif
    }
    #if os(iOS)
    private func registerIfAllowed(_ status: DevicePermissionStatus) {
        guard status == .allowed || status == .limited else { registrationRequested = false; return }
        guard !registrationRequested else { return }
        registrationRequested = true
        registerNotification()
    }
    public static func notificationStatus(_ value: UNAuthorizationStatus) -> DevicePermissionStatus {
        switch value { case .notDetermined: .notAsked; case .denied: .denied; case .authorized: .allowed; case .provisional, .ephemeral: .limited; @unknown default: .unavailable }
    }
    public static func cameraStatus(_ value: AVAuthorizationStatus) -> DevicePermissionStatus {
        switch value { case .notDetermined: .notAsked; case .restricted: .restricted; case .denied: .denied; case .authorized: .allowed; @unknown default: .unavailable }
    }
    public static func photoStatus(_ value: PHAuthorizationStatus) -> DevicePermissionStatus {
        switch value { case .notDetermined: .notAsked; case .restricted: .restricted; case .denied: .denied; case .authorized: .allowed; case .limited: .limited; @unknown default: .unavailable }
    }
    #endif
}
