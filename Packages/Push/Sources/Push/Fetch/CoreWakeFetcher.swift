// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// `WakeFetching` over the core's wake-fetch entry point (`WakeFetchHost`): one fetch, no decryption, no apply.
public struct CoreWakeFetcher: WakeFetching {
    private let dataRoot: URL
    public init(dataRoot: URL) { self.dataRoot = dataRoot }
    public init?(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard let container = SharedContainer.containerURL(info: info) else { return nil }
        self.init(dataRoot: container.appendingPathComponent("ramflux", isDirectory: true))
    }
    public func fetch(account: String, wakeID: String, deadline: ContinuousClock.Instant) async -> WakeFetchOutcome {
        let remaining = ContinuousClock.now.duration(to: deadline)
        let milliseconds = max(0, min(Int64(WakeFetchHost.maxBudgetMilliseconds), remaining.components.seconds * 1_000 + remaining.components.attoseconds / 1_000_000_000_000_000))
        guard milliseconds > 0 else { return .deadline }
        let absolute = UInt64(Date().timeIntervalSince1970 * 1_000) + UInt64(milliseconds)
        do {
            switch try await WakeFetchHost.fetch(dataRoot: dataRoot, accountID: account, deadlineUnixMilliseconds: absolute) {
            case .fetched(let count): return .fetched(count)
            case .busy: return .busy
            case .locked: return .locked
            case .deadline: return .deadline
            }
        } catch let failure as CoreFailure { return .failed(failure.rawCode) }
        catch { return .failed(-1) }
    }
}
