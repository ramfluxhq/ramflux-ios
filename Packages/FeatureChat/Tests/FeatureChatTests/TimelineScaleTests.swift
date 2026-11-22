// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
@testable import AppData
@testable import FeatureChat

/// Scale rule 10: the chat against a synthetic 50,000-message history. The window must stay
/// bounded while paging back, and change batches must patch it without reprojecting history.
/// Timings are printed for the report; they are not pass criteria.
@Suite(.timeLimit(.minutes(2))) @MainActor struct TimelineScaleTests {
    @Test func fiftyThousandRowHistoryPagesBackWithABoundedWindow() async {
        var rows: [MessageRecord] = []
        rows.reserveCapacity(50_000)
        for index in 0..<50_000 {
            let ms: Int64 = 100_000_000 - Int64(index) * 1_000
            rows.append(record("s" + String(index), own: index % 3 == 0, text: "Message " + String(index), ms: ms))
        }
        let fake = ChatFake(history: rows)
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        let clock = ContinuousClock()
        let start = clock.now
        model.send(.appeared); await model.settle()
        let opened = clock.now - start
        var pages = 0
        let pagingStart = clock.now
        while model.state.olderAvailable, pages < 40 { model.send(.loadOlder); await model.settle(); pages += 1 }
        let paging = clock.now - pagingStart
        #expect(model.state.messages.count == TimelineWindow.defaultCapacity)
        #expect(model.state.detached)
        let projectionStart = clock.now
        let items = TimelineProjection.items(model.state.messages, calendar: .current, unreadAnchorID: nil)
        let projection = clock.now - projectionStart
        #expect(items.count >= model.state.messages.count)
        var window = TimelineWindow()
        window.reset(MessageWindowPage(records: Array(rows.prefix(50)), nextBefore: MessageWindowPage.testCursor(50), snapshotSequence: 1))
        var live: [MessageChangeBatch.Change] = []
        for index in 0..<100 { live.append(.row(record("live" + String(index), ms: 200_000_000 + Int64(index)))) }
        let batch = MessageChangeBatch(changes: live, nextAfter: 2, more: false)
        let applyStart = clock.now
        window.apply(batch)
        let apply = clock.now - applyStart
        #expect(window.records.count == 150)
        print("SCALE chat 50k: open \(opened), \(pages) older pages \(paging), projection of \(items.count) rows \(projection), 100-row change batch \(apply)")
        model.send(.disappeared)
    }
}
