// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct CallSignalArguments: Equatable, Sendable {
    public let expected: CallRecord
    public let signal: CallSignal
    public init(expected: CallRecord, signal: CallSignal) { self.expected = expected; self.signal = signal }
}
