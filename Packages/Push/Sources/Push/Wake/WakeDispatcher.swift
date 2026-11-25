// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// Maps wake class, entry point and fetch outcome to a result (design table 6.1). The app process, the
/// notification service extension and the debug injector all call it; nothing else decides what a wake shows.
public struct WakeDispatcher: Sendable {
    private let fetcher: (any WakeFetching)?
    private let registry: RouteRegistry?
    public init(fetcher: (any WakeFetching)?, registry: RouteRegistry?) { self.fetcher = fetcher; self.registry = registry }

    public func handle(_ signal: WakeSignal, deadline: ContinuousClock.Instant) async -> WakeResult {
        switch signal.wakeClass {
        case .message: return await message(signal, deadline: deadline)
        case .call:
            switch signal.source {
            case .pushKit, .debugInjector: return .ringCall(CallWake())
            default: return .showGeneric(.call)
            }
        case .clear: return signal.source == .remoteNotification ? .clearMessages : .showGeneric(.message)
        case .test: return .showGeneric(.test)
        case .unknown: PushLog.wake.notice("push.wake.unknown"); return .showGeneric(.message)
        }
    }

    private func message(_ signal: WakeSignal, deadline: ContinuousClock.Instant) async -> WakeResult {
        guard let tag = signal.routeTag, let wakeID = signal.wakeID, let account = registry?.account(for: tag), let fetcher else {
            PushLog.wake.notice("push.wake.unknown")
            return .showGeneric(.message)
        }
        switch await fetcher.fetch(account: account, wakeID: wakeID, deadline: deadline) {
        case .fetched: PushLog.wake.notice("push.fetch.fetched"); return .showGeneric(.message)
        case .busy: PushLog.wake.notice("push.fetch.busy"); return .showGeneric(.message)
        case .deadline: PushLog.wake.notice("push.fetch.deadline"); return .showGeneric(.message)
        case .failed(let code): PushLog.wake.notice("push.fetch.failed code=\(code, privacy: .public)"); return .showGeneric(.message)
        case .locked:
            // Unreadable route map means before the first unlock since boot; readable means an explicitly locked account.
            let beforeFirstUnlock = registry?.isReadable() == false
            PushLog.wake.notice("push.fetch.locked beforeFirstUnlock=\(beforeFirstUnlock, privacy: .public)")
            return beforeFirstUnlock ? .showUnlockNotice : .showGeneric(.message)
        }
    }
}
