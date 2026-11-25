// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
@testable import AppData

private actor FakeCenter: MessageNotificationCenter {
    private(set) var posted: [String] = []
    private(set) var badges: [Int] = []
    private(set) var cleared = 0
    func post(token: String) { posted.append(token) }
    func setBadge(_ count: Int) { badges.append(count) }
    func removeDelivered() { cleared += 1 }
}

private actor FakeDirectory: ConversationsRepository {
    var rows: [ConversationRecord] = []
    private(set) var reads = 0
    private(set) var limits: [Int] = []
    let live = Mutex<AsyncStream<RepositoryUpdate>.Continuation?>(nil)
    let observed = Mutex(0)
    func set(_ rows: [ConversationRecord]) { self.rows = rows }
    func page(account: String, cursor: String?, limit: Int) -> RepositoryResult<ConversationPage> { reads += 1; limits.append(limit); return .success(ConversationPage(rows: rows, nextCursor: nil)) }
    func pendingRequests(account: String) -> RepositoryResult<UInt> { .success(0) }
    func search(account: String, query: String) -> RepositoryResult<[ConversationRecord]> { .success([]) }
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        live.withLock { $0?.finish(); $0 = pair.continuation }; observed.withLock { $0 += 1 }
        return RepositoryObservation(stream: pair.stream)
    }
    nonisolated func invalidate() { live.withLock { _ = $0?.yield(.invalidated) } }
}

private func row(_ id: String, unread: UInt?, muted: Bool = false) -> ConversationRecord { ConversationRecord(id: id, title: "Peer " + id, preview: "secret text", unreadCount: unread, muted: muted) }

@MainActor private func until(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<2000 { if await condition() { return }; try? await Task.sleep(for: .milliseconds(1)) }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct MessageNotifierTests {
    @Test func planMapsRisingUnreadToNotificationsOnlyWhileInactive() {
        let rows = [row("a", unread: 3), row("b", unread: 1), row("m", unread: 9, muted: true), row("n", unread: 2), row("z", unread: nil)]
        let previous: [String: UInt] = ["a": 1, "b": 1, "m": 0]
        #expect(MessageNotifier.plan(previous: previous, rows: rows, active: false) == MessageNotificationPlan(notify: ["a", "n"], badge: 6))
        #expect(MessageNotifier.plan(previous: previous, rows: rows, active: true) == MessageNotificationPlan(notify: [], badge: 6))
        #expect(MessageNotifier.plan(previous: nil, rows: rows, active: false).notify.isEmpty, "the first read is a baseline")
    }
    @Test func eventsDriveGenericNotificationsWithInMemoryRoutes() async {
        let directory = FakeDirectory(), center = FakeCenter()
        await directory.set([row("a", unread: 0)])
        let notifier = MessageNotifier(conversations: directory, center: center, slot: { _ in "t1" })
        notifier.follow(account: "acc")
        await until { directory.observed.withLock { $0 } == 1 }
        directory.invalidate()
        await until { await directory.reads == 1 }
        notifier.setActive(false)
        await directory.set([row("a", unread: 2)])
        directory.invalidate()
        await until { await center.posted.count == 1 }
        #expect(await center.posted == ["t1"])
        #expect(notifier.account(for: "t1") == "acc")
        #expect(await center.badges.last == 2)
        #expect(await directory.limits.allSatisfy { $0 == MessageNotifier.defaultWindow })
        notifier.setActive(true)
        await until { await center.cleared == 1 }
        #expect(notifier.account(for: "t1") != nil, "the tap that activates the app arrives after activation")
        notifier.follow(account: nil)
    }
    @Test func groupRowsRaiseTheSameSingleSlot() async {
        let directory = FakeDirectory(), center = FakeCenter()
        let notifier = MessageNotifier(conversations: directory, center: center, slot: { _ in "g" })
        notifier.setActive(false)
        notifier.follow(account: "acc")
        await until { directory.observed.withLock { $0 } == 1 }
        directory.invalidate(); await until { await directory.reads == 1 }
        await directory.set([ConversationRecord(id: "grp", title: "Team", preview: "", unreadCount: 1, kind: "group", groupID: "team")])
        directory.invalidate(); await until { await center.posted.count == 1 }
        #expect(notifier.account(for: "g") == "acc", "a group row raises the same single slot")
        notifier.follow(account: nil)
    }
    @Test func switchingAccountsDropsRoutesAndRebaselines() async {
        let directory = FakeDirectory(), center = FakeCenter()
        let notifier = MessageNotifier(conversations: directory, center: center, slot: { _ in "tok" })
        notifier.setActive(false)
        await directory.set([row("a", unread: 0)])
        notifier.follow(account: "one")
        await until { directory.observed.withLock { $0 } == 1 }
        directory.invalidate(); await until { await directory.reads == 1 }
        await directory.set([row("a", unread: 1)])
        directory.invalidate(); await until { await center.posted.count == 1 }
        notifier.follow(account: "two")
        #expect(notifier.account(for: "tok") == nil)
        await until { directory.observed.withLock { $0 } == 2 }
        await directory.set([row("a", unread: 5)])
        directory.invalidate(); await until { await directory.reads == 3 }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await center.posted.count == 1, "a new account's first read must not notify")
        notifier.follow(account: nil)
    }
}
