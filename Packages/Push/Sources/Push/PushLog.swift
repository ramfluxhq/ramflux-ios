// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import os

/// Loggers of the push path. Subsystem `org.ramflux.push`; messages are fixed codes only, never a token, route tag,
/// wake id, account id or text.
public enum PushLog {
    public static let subsystem = "org.ramflux.push"
    public static let nse = Logger(subsystem: subsystem, category: "nse")
    public static let token = Logger(subsystem: subsystem, category: "token")
}
