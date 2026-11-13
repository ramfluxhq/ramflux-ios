// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct CallSignalAttempt: Equatable, Sendable {
    public let expected: CallRecord
    public let signal: CallSignal
    public let operationID: String
    public init(expected: CallRecord, signal: CallSignal, operationID: String) { self.expected = expected; self.signal = signal; self.operationID = operationID }
}
