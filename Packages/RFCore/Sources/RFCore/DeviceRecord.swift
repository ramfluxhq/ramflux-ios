// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct DeviceRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let isLocal: Bool
    public let capabilities: [String]
    public let webOrigin: String?
    public init(id: String, isLocal: Bool, capabilities: [String], webOrigin: String? = nil) {
        self.id = id; self.isLocal = isLocal; self.capabilities = capabilities; self.webOrigin = webOrigin
    }
}
