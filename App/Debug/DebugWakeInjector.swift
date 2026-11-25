// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_DEBUG_WAKE
import Foundation
import Push

/// Debug-only entry points that run a wake through the same dispatcher, processor and call handler as the real
/// ones, with source `.debugInjector` (design 6.4). It is compiled out of Release (scripts/check-release-symbols.sh).
///   launch argument `-RFDebugWake call` or `-RFDebugWake message`: a cold-start wake, before the shell loads;
///   payload key `rf_debug.as` on an alert push to the foreground app (`simctl push` refuses silent pushes on this
///   runtime): `voip` rings the call wake, `nse` runs the message path the extension runs.
enum DebugWakeInjector {
    enum Mode: String { case voip, nse }
    static func launchMode(arguments: [String] = ProcessInfo.processInfo.arguments) -> Mode? {
        guard let index = arguments.firstIndex(of: "-RFDebugWake"), arguments.indices.contains(index + 1) else { return nil }
        switch arguments[index + 1] { case "call": return .voip; case "message": return .nse; default: return nil }
    }
    static func mode(userInfo: [AnyHashable: Any]) -> Mode? {
        ((userInfo["rf_debug"] as? [String: Any])?["as"] as? String).flatMap(Mode.init(rawValue:))
    }
}
#endif
