// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData

/// One row of the chat timeline.
enum TimelineItem: Equatable, Sendable {
    /// The start of a calendar day; shown as a date chip above that day's first message.
    case day(Date)
    /// The divider above the first unread message.
    case unread
    case message(MessageRecord)

    var id: String {
        switch self {
        case .day(let start): "day:" + String(Int64(start.timeIntervalSince1970))
        case .unread: "unread"
        case .message(let record): "message:" + record.id
        }
    }
}

enum TimelineProjection {
    /// The SDK page is newest first. The timeline is oldest at the top and newest at the bottom.
    static func chronological(_ messages: [MessageRecord]) -> [MessageRecord] {
        Array(messages.reversed())
    }

    /// Chronological rows with a day chip where the calendar day changes and the unread divider
    /// above `unreadAnchorID`. Messages without a valid timestamp start no new day.
    static func items(_ messages: [MessageRecord], calendar: Calendar, unreadAnchorID: String?) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var currentDay: Date?
        for message in chronological(messages) {
            if let day = day(of: message, calendar: calendar), day != currentDay {
                items.append(.day(day))
                currentDay = day
            }
            if message.id == unreadAnchorID { items.append(.unread) }
            items.append(.message(message))
        }
        return items
    }

    static func date(of message: MessageRecord) -> Date? {
        guard let timestamp = message.timestamp, (0...253402300799).contains(timestamp) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    static func day(of message: MessageRecord, calendar: Calendar) -> Date? {
        date(of: message).map { calendar.startOfDay(for: $0) }
    }

    /// The date chip label in the active locale and calendar: "Today" and "Yesterday" where the
    /// locale has them, otherwise the medium date.
    static func dayLabel(_ day: Date, locale: Locale, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: day)
    }
}
