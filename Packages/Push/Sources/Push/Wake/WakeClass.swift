// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// The class of a wake (`rf.c`). Anything else is `unknown`.
public enum WakeClass: String, Sendable {
    case message = "m", call, clear = "x", test = "t", unknown
    public init(code: String?) { self = code.flatMap { Self(rawValue: $0) } ?? .unknown }
}
