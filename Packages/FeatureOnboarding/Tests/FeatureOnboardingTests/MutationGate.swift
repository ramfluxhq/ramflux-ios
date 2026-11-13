// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
actor MutationGate {
    nonisolated let entered = AsyncStream<Void>.makeStream()
    nonisolated let released = AsyncStream<Void>.makeStream()
    func wait() async { entered.continuation.yield(()); var stream = released.stream.makeAsyncIterator(); _ = await stream.next() }
    nonisolated func release() { released.continuation.yield(()); released.continuation.finish() }
}
