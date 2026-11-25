// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// One wake as the dispatcher sees it, whichever process or entry point received it.
public struct WakeSignal: Sendable, CustomStringConvertible {
    public enum Source: String, Sendable { case notificationService, remoteNotification, pushKit, debugInjector }
    public let wakeClass: WakeClass
    public let routeTag: String?
    public let wakeID: String?
    public let source: Source
    public init(wakeClass: WakeClass, routeTag: String?, wakeID: String?, source: Source) {
        self.wakeClass = wakeClass; self.routeTag = routeTag; self.wakeID = wakeID; self.source = source
    }
    public init(payload: WakePayload, source: Source) { self.init(wakeClass: payload.wakeClass, routeTag: payload.routeTag, wakeID: payload.wakeID, source: source) }
    public var description: String { "wake(class: \(wakeClass.rawValue), source: \(source.rawValue))" }
}
