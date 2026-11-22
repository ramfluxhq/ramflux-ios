// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import SwiftUI
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

    @Test func dayChipsStartEachCalendarDayAndTheUnreadDividerPrecedesItsMessage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let dayOne: Int64 = 1_767_225_600 // 2026-01-01T00:00:00Z
        let rows = [
            MessageRecord(id: "c", sender: "", kind: .text("third"), isOwn: false, timestamp: dayOne + 86_400 + 60),
            MessageRecord(id: "b", sender: "", kind: .text("second"), isOwn: true, timestamp: dayOne + 7_200),
            MessageRecord(id: "a", sender: "", kind: .text("first"), isOwn: false, timestamp: dayOne + 3_600),
            MessageRecord(id: "z", sender: "", kind: .text("undated"), isOwn: false),
        ]
        let items = TimelineProjection.items(rows, calendar: calendar, unreadAnchorID: "c")
        #expect(items.map(\.id) == ["message:z", "day:1767225600", "message:a", "message:b", "day:1767312000", "unread", "message:c"])
        #expect(TimelineProjection.items(rows, calendar: calendar, unreadAnchorID: nil).contains(.unread) == false)
    }

    @Test func dayLabelUsesTheLocaleAndRelativeNames() {
        let today = Calendar.current.startOfDay(for: Date())
        #expect(TimelineProjection.dayLabel(today, locale: Locale(identifier: "en"), calendar: .current) == "Today")
        #expect(TimelineProjection.dayLabel(today, locale: Locale(identifier: "zh-CN"), calendar: .current) == "今天")
        #expect(!TimelineProjection.dayLabel(today, locale: Locale(identifier: "ar"), calendar: .current).isEmpty)
    }

    @Test func unreadDividerCopyResolvesInEveryShippedLocale() {
        for identifier in ["en", "zh-CN"] {
            let value = FeatureChatStrings.text("chat.timeline.unreadDivider", locale: Locale(identifier: identifier))
            #expect(value != "chat.timeline.unreadDivider" && !value.isEmpty)
        }
    }
}

/// The bubble side follows own versus incoming; the text direction inside follows the content.
@Suite(.timeLimit(.minutes(1))) struct BubblePlacementTests {
    @Test(arguments: [
        (true, "مرحبا، هل راجعت الملف؟", LayoutDirection.leftToRight, BubblePlacement.Side.trailing, LayoutDirection.rightToLeft),
        (false, "مرحبا، هل راجعت الملف؟", .leftToRight, .leading, .rightToLeft),
        (true, "I will take a look.", .rightToLeft, .trailing, .leftToRight),
        (false, "I will take a look.", .rightToLeft, .leading, .leftToRight),
        (false, "@nova مرحبا", .leftToRight, .leading, .rightToLeft),
        (true, "12:30 👍", .rightToLeft, .trailing, .rightToLeft),
        (true, "12:30 👍", .leftToRight, .trailing, .leftToRight),
    ])
    func placement(_ isOwn: Bool, _ text: String, _ ui: LayoutDirection, _ side: BubblePlacement.Side, _ direction: LayoutDirection) {
        let placement = BubblePlacement(isOwn: isOwn, text: text, uiDirection: ui)
        #expect(placement.side == side)
        #expect(placement.textDirection == direction)
    }

    @Test func overrideCharactersDoNotDecideTheDirection() {
        // U+202E would make the English text read right to left if it were honoured.
        let placement = BubblePlacement(isOwn: false, text: "\u{202E}hello", uiDirection: .rightToLeft)
        #expect(placement.textDirection == .leftToRight)
    }
}
