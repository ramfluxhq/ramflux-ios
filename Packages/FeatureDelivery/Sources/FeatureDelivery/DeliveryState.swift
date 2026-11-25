// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData
public struct DeliveryState: Equatable, Sendable {
    public var snapshot = DeliverySnapshot()
    /// `sent`, `failed` or nil: the answer to the last self-test request.
    public var selfTest: SelfTest?
    public enum SelfTest: Equatable, Sendable { case sent, failed }
    public init() {}
}
