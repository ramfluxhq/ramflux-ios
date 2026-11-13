// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
enum SettingsModal: Identifiable {
    case revoke(DeviceRecord), backup(BackupIntent), share(URL)
    var id: String { switch self { case .revoke(let device): "revoke:" + device.id; case .backup(let intent): intent.id; case .share(let url): "share:" + url.lastPathComponent } }
}
