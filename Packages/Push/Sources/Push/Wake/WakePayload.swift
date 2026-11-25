// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The `rf` object of a push: `{v: 1, c, t, w}` (class, route tag, wake id). A wrong version, a string-typed or
/// incomplete `rf` gives the `unknown` class; sibling keys are ignored. The description shows the class only.
public struct WakePayload: Sendable, CustomStringConvertible {
    public let wakeClass: WakeClass
    public let routeTag: String?
    public let wakeID: String?
    public init(userInfo: [AnyHashable: Any]) {
        guard let rf = userInfo["rf"] as? [String: Any], (rf["v"] as? Int) == 1,
              let code = rf["c"] as? String, let tag = rf["t"] as? String, let wake = rf["w"] as? String,
              !tag.isEmpty, !wake.isEmpty, wake.count <= 64 else {
            wakeClass = .unknown; routeTag = nil; wakeID = nil; return
        }
        wakeClass = WakeClass(code: code); routeTag = tag; wakeID = wake
    }
    public var description: String { "wake(class: \(wakeClass.rawValue))" }
}
