// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
#if DEBUG
import os
#endif

/// Debug-build trace of the event path (topics, cursors, counts; never payloads, ids or text), read
/// with `log show --predicate 'subsystem == "org.ramflux.ios"'` when a live update goes missing.
public enum EventDiagnostics {
    #if DEBUG
    private static let logger = Logger(subsystem: "org.ramflux.ios", category: "events")
    #endif
    /// A failed SDK call: the method and the typed code, name and reason (never the payload).
    public static func failed(_ method: String, _ error: any Error) {
        note("\(method) failed " + describe(error))
    }
    public static func describe(_ error: any Error) -> String {
        guard let failure = error as? CoreFailure else { return String(describing: error).prefix(120).description }
        return "code=\(failure.rawCode) name=\(failure.typedName ?? "-") reason=\(failure.reasonCode ?? "-")"
    }
    public static func note(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        // Notice level, so the simulator keeps the trace for `log show` (debug messages are not persisted).
        logger.notice("\(text, privacy: .public)")
        #endif
    }
}
