// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct FrozenSend: Equatable, Sendable, CustomStringConvertible {
    public let operationID: String
    public let text: String
    public var description: String { "FrozenSend" }
    public init(operationID: String, text: String) { self.operationID = operationID; self.text = text }
}
