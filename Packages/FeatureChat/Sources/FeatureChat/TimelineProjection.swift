// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import AppData
import FeatureCards

/// One row of the chat timeline. Every row has a stable id derived from SDK ids (or the local
/// operation id for unadmitted sends), never from display text or position.
enum TimelineItem: Equatable, Sendable {
    /// Shown at the top while an older page loads.
    case history
    /// The start of a calendar day; shown as a date chip above that day's first message.
    case day(Date)
    /// The divider above the first unread message.
    case unread
    case message(MessageRecord, MessageMedia)
    /// A send the SDK has not admitted yet (queued, sending or failed).
    case outbox(OutboxEntry)

    var id: String {
        switch self {
        case .history: "history"
        case .day(let start): "day:" + String(Int64(start.timeIntervalSince1970))
        case .unread: "unread"
        case .message(let record, _): "message:" + record.id
        case .outbox(let entry): "outbox:" + entry.operationID
        }
    }
}

/// The transfer states of one message's attachments, so a finished download reconfigures only
/// that row.
struct MessageMedia: Equatable, Sendable {
    var states: [String: MediaTransferState] = [:]
    var revealed: Set<String> = []
    /// The agent surface this message carried, if any.
    var card: SurfaceCardState?
    /// The incoming message's author is a participant the SDK verified as an AI agent.
    var authorIsAgent = false
    static let none = MessageMedia()
}

enum TimelineProjection {
    /// The SDK page is newest first. The timeline is oldest at the top and newest at the bottom.
    static func chronological(_ messages: [MessageRecord]) -> [MessageRecord] {
        Array(messages.reversed())
    }

    /// Chronological rows with a day chip where the calendar day changes, the unread divider
    /// above `unreadAnchorID`, and unadmitted sends after the last message. Messages without a
    /// valid timestamp start no new day. Linear in the window size; the window is bounded.
    static func items(_ messages: [MessageRecord], outbox: [OutboxEntry] = [], calendar: Calendar, unreadAnchorID: String?, loadingOlder: Bool = false, media: [String: MediaTransferState] = [:], revealed: Set<String> = [], cards: [String: SurfaceCardState] = [:], agentAuthors: Set<String> = []) -> [TimelineItem] {
        var items: [TimelineItem] = []
        items.reserveCapacity(messages.count + outbox.count + 8)
        if loadingOlder { items.append(.history) }
        var currentDay: Date?
        for message in chronological(messages) {
            if let day = day(of: message, calendar: calendar), day != currentDay {
                items.append(.day(day))
                currentDay = day
            }
            if message.id == unreadAnchorID { items.append(.unread) }
            var slice = MessageMedia.none
            for attachment in message.attachments {
                if let value = media[attachment.id] { slice.states[attachment.id] = value }
                if revealed.contains(attachment.id) { slice.revealed.insert(attachment.id) }
            }
            slice.card = cards[message.id]
            slice.authorIsAgent = message.isOwn == false && message.authorAnchor.map(agentAuthors.contains) == true
            items.append(.message(message, slice))
        }
        for entry in outbox { items.append(.outbox(entry)) }
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
    /// locale has them, otherwise the medium date. Formatters are cached per locale, calendar
    /// and time zone, because building one per row is expensive.
    static func dayLabel(_ day: Date, locale: Locale, calendar: Calendar) -> String {
        DayFormatters.shared.formatter(locale: locale, calendar: calendar).string(from: day)
    }
}

/// A small cache of relative day formatters. `DateFormatter` is thread safe for formatting on
/// the supported OS versions; the cache itself is guarded by a mutex.
final class DayFormatters: Sendable {
    static let shared = DayFormatters()
    private struct Key: Hashable { let locale: String; let calendar: Calendar.Identifier; let zone: String }
    private let cache = Mutex<[Key: DateFormatterBox]>([:])
    func formatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let key = Key(locale: locale.identifier, calendar: calendar.identifier, zone: calendar.timeZone.identifier)
        return cache.withLock { cache in
            if let box = cache[key] { return box.formatter }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.doesRelativeDateFormatting = true
            if cache.count > 16 { cache.removeAll() }
            cache[key] = DateFormatterBox(formatter: formatter)
            return formatter
        }
    }
}
private final class DateFormatterBox: @unchecked Sendable {
    let formatter: DateFormatter
    init(formatter: DateFormatter) { self.formatter = formatter }
}
