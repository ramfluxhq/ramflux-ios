// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import UserNotifications
import AVFoundation
import Photos
import AppData
@MainActor final class DevicePermissionPlatformTests: XCTestCase {
    func testNativeAuthorizationEnumsKeepDeniedUndeterminedAndLimitedDistinct() {
        XCTAssertEqual(NativeDevicePermissionsRepository.notificationStatus(.notDetermined), .notAsked)
        XCTAssertEqual(NativeDevicePermissionsRepository.notificationStatus(.denied), .denied)
        XCTAssertEqual(NativeDevicePermissionsRepository.notificationStatus(.authorized), .allowed)
        XCTAssertEqual(NativeDevicePermissionsRepository.notificationStatus(.provisional), .limited)
        XCTAssertEqual(NativeDevicePermissionsRepository.notificationStatus(.ephemeral), .limited)
        XCTAssertEqual(NativeDevicePermissionsRepository.cameraStatus(.restricted), .restricted)
        XCTAssertEqual(NativeDevicePermissionsRepository.cameraStatus(.notDetermined), .notAsked)
        XCTAssertEqual(NativeDevicePermissionsRepository.cameraStatus(.denied), .denied)
        XCTAssertEqual(NativeDevicePermissionsRepository.cameraStatus(.authorized), .allowed)
        XCTAssertEqual(NativeDevicePermissionsRepository.photoStatus(.restricted), .restricted)
        XCTAssertEqual(NativeDevicePermissionsRepository.photoStatus(.limited), .limited)
        XCTAssertEqual(NativeDevicePermissionsRepository.photoStatus(.authorized), .allowed)
        XCTAssertEqual(NativeDevicePermissionsRepository.photoStatus(.denied), .denied)
        XCTAssertEqual(NativeDevicePermissionsRepository.photoStatus(.notDetermined), .notAsked)
    }
    func testBuiltAppContainsOnlyLocalizedMinimalUsageDescriptions() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(Set(info.keys.filter { $0.hasSuffix("UsageDescription") }), Set(["NSMicrophoneUsageDescription", "NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription"]))
        XCTAssertEqual(info["UIBackgroundModes"] as? [String], ["remote-notification"])
        for (language, camera) in [("en", "Ramflux uses the camera only while taking a photo or scanning a QR code."), ("zh-CN", "Ramflux 仅在拍照或扫描二维码时使用相机。")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let localized = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(localized.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist"), camera)
            for key in ["NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
                XCTAssertNotEqual(localized.localizedString(forKey: key, value: nil, table: "InfoPlist"), key)
            }
        }
    }
    func testSnapshotReadsRealOSStatusesAndNeverAsksForMicrophone() async {
        let repository = NativeDevicePermissionsRepository()
        let snapshot = await repository.snapshot()
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        XCTAssertEqual(snapshot[.notifications], NativeDevicePermissionsRepository.notificationStatus(notificationSettings.authorizationStatus))
        XCTAssertEqual(snapshot[.camera], NativeDevicePermissionsRepository.cameraStatus(AVCaptureDevice.authorizationStatus(for: .video)))
        XCTAssertEqual(snapshot[.photoAdd], NativeDevicePermissionsRepository.photoStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly)))
        XCTAssertEqual(snapshot[.photoPicker], .notRequired); XCTAssertEqual(snapshot[.files], .notRequired)
        XCTAssertEqual(snapshot[.incomingCalls], .unavailable)
        let result = await repository.request(.microphone)
        guard case .failure(.unsupported) = result else { XCTFail("Unavailable media must not request microphone access"); return }
    }
}
