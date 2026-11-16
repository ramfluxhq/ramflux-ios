// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import AppData
@testable import FeatureChat

@Suite(.timeLimit(.minutes(1))) struct TimelineProjectionTests {
    @Test func newestSdkRowBecomesTheBottomRow() {
        let older = MessageRecord(id: "older", sender: "", kind: .text("older"), isOwn: false)
        let newer = MessageRecord(id: "newer", sender: "", kind: .text("newer"), isOwn: true)
        let page = TimelineProjection.chronological([newer, older])
        #expect(page.map(\.id) == ["older", "newer"])
        let arrived = MessageRecord(id: "arrived", sender: "", kind: .text("arrived"), isOwn: false)
        let next = TimelineProjection.chronological([arrived, newer, older])
        #expect(next.last?.id == "arrived")
        #expect(next.first?.id == "older")
    }
}
