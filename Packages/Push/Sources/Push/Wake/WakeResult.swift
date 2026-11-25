// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// A call wake that must ring now. It carries no caller: the placeholder names none.
public struct CallWake: Sendable, Equatable { public init() {} }

/// What a wake leads to. The only place that decides it is `WakeDispatcher`.
public enum WakeResult: Sendable, Equatable {
    case showGeneric(GenericContent.Kind)
    case showUnlockNotice
    /// Only with the filtering entitlement (not declared yet).
    case suppress
    case ringCall(CallWake)
    case clearMessages
    case ignore
}
