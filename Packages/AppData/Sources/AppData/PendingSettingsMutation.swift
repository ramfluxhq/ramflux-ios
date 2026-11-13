// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct PendingSettingsMutation: Equatable, Sendable {
    public let change: SettingsMutation
    public let operationID: String
    public init(change: SettingsMutation, operationID: String) { self.change = change; self.operationID = operationID }
}
