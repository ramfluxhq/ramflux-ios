// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import AppData
@testable import FeatureConversations
/// Synthetic directory paged by id like the SDK, with activity unrelated to id order.
private final class SyntheticDirectory: ConversationsRepository, Sendable {
    let total: Int
    let reads = Mutex(0)
    init(total: Int) { self.total = total }
    private func id(_ index: Int) -> String { String(format: "c%06d", index) }
    func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<ConversationPage> {
        reads.withLock { $0 += 1 }
        let start = cursor.flatMap { Int($0.dropFirst()) }.map { $0 + 1 } ?? 0
        let end = min(start + limit, total)
        let rows = (start..<end).map { index in
            ConversationRecord(id: id(index), title: "Conversation \(index)", preview: "", lastActivity: Int64(1_700_000_000 + (index * 7919) % total), unreadCount: UInt(index % 3))
        }
        return .success(ConversationPage(rows: rows, nextCursor: end < total ? id(end - 1) : nil))
    }
    func pendingRequests(account: String) async -> RepositoryResult<UInt> { .success(3) }
    func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.unsupported) }
    func observe(account: String) async -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
}
@Suite(.timeLimit(.minutes(1))) struct ConversationsWindowTests {
    @Test func projectionSortsRecentFirstAndLabelsTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            ConversationRecord(id: "old", title: "o", preview: "", lastActivity: 1_700_000_000),
            ConversationRecord(id: "none", title: "n", preview: ""),
            ConversationRecord(id: "today", title: "t", preview: "", lastActivity: 1_800_000_000 - 60),
            ConversationRecord(id: "yesterday", title: "y", preview: "", lastActivity: 1_800_000_000 - 86_400),
            ConversationRecord(id: "today", title: "duplicate", preview: "", lastActivity: 1),
        ]
        let projected = ConversationsWindow.project(rows, locale: Locale(identifier: "en_US"), now: now)
        #expect(projected.map(\.id) == ["today", "yesterday", "old", "none"])
        #expect(projected[1].timeLabel == "Yesterday"); #expect(!projected[0].timeLabel.isEmpty); #expect(projected[3].timeLabel.isEmpty)
        #expect(ConversationsWindow.project(rows, locale: Locale(identifier: "zh-CN"), now: now)[1].timeLabel == "昨天")
    }
    @Test func evictedWindowDropsLaterRowsAboveItsTop() async {
        let source = SyntheticDirectory(total: 2_000)
        var window = ConversationsWindow()
        let locale = Locale(identifier: "en_US"), now = Date()
        if case .success(let next) = await ConversationsWindow.load(source, account: "a", pages: 1, locale: locale, now: now) { window = next }
        while window.pages < 12, case .success(let next) = await window.appending(source, account: "a", locale: locale, now: now) { window = next }
        #expect(window.evictedAbove); #expect(window.rows.count == ConversationsWindow.maxRows)
        let top = window.rows[0]
        if case .success(let next) = await window.appending(source, account: "a", locale: locale, now: now) { window = next }
        #expect(window.rows.allSatisfy { !ConversationsWindow.precedes($0, top) })
        #expect(window.rows.count == ConversationsWindow.maxRows)
    }
    @Test @MainActor func fiftyThousandRowSourceLoadsPageByPageAndStaysBounded() async {
        let source = SyntheticDirectory(total: 50_000)
        let model = ConversationsViewModel(repository: source, account: "a", emit: { _ in })
        let clock = ContinuousClock()
        let first = await clock.measure { model.send(.refresh); await model.settle() }
        #expect(model.state.rows.count == 50); #expect(model.state.canLoadMore); #expect(source.reads.withLock { $0 } <= 2)
        #expect(model.state.strangersUnread == 3)
        var more = Duration.zero
        for _ in 0..<19 { more += await clock.measure { model.send(.loadMore); await model.settle() } }
        // 20 pages read, but the window keeps at most maxRows, evicting from the top.
        #expect(model.state.rows.count == ConversationsWindow.maxRows); #expect(Set(model.state.rows.map(\.id)).count == ConversationsWindow.maxRows)
        #expect(model.state.canLoadBefore)
        let activity = model.state.rows.compactMap(\.lastActivity)
        #expect(activity == activity.sorted(by: >))
        // Scroll far: 980 more pages (the whole 50,000-row directory); memory stays bounded.
        var far = Duration.zero
        while model.state.canLoadMore { far += await clock.measure { model.send(.loadMore); await model.settle() } }
        #expect(model.state.rows.count <= ConversationsWindow.maxRows); #expect(!model.state.rows.isEmpty)
        let tail = model.state.rows.compactMap(\.lastActivity)
        #expect(tail == tail.sorted(by: >))
        // Reaching the first row of an evicted window reloads the top of the list.
        let before = await clock.measure { model.send(.loadBefore); await model.settle() }
        #expect(model.state.rows.count == ConversationsWindow.refreshPages * ConversationsWindow.pageSize); #expect(!model.state.canLoadBefore)
        let refresh = await clock.measure { model.send(.refresh); await model.settle() }
        #expect(model.state.rows.count == ConversationsWindow.refreshPages * ConversationsWindow.pageSize)
        print("CONVERSATIONS_50K first=\(first) loadMore19=\(more) scrollToEnd=\(far) loadBefore=\(before) refresh=\(refresh) reads=\(source.reads.withLock { $0 })")
        model.send(.disappeared)
    }
}
