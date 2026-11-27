// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
enum SettingsModal: Identifiable {
    case revoke(DeviceRecord), changeCode, removeLocal(String), claimUsername
    var id: String { switch self { case .revoke(let device): "revoke:" + device.id; case .changeCode: "changeCode"; case .removeLocal(let account): "removeLocal:" + account; case .claimUsername: "claimUsername" } }
}
