// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData

/// The loaded part of the conversation directory, shown recent first.
///
/// The SDK pages `conversation.directory` by conversation id and has no activity-ordered cursor, so
/// only the loaded rows are sorted by `last_activity`; a recent conversation on a page not yet loaded
/// appears once the user scrolls far enough. The window never fetches the whole directory: it follows
/// `next_cursor` one page at a time, and a refresh re-reads at most `refreshPages` pages.
public struct ConversationsWindow: Sendable, Equatable {
    public static let pageSize = NativeConversationsRepository.pageLimit
    /// Pages re-read on a refresh (about 300 rows); scrolling further loads more again.
    public static let refreshPages = 6
    public private(set) var rows: [ConversationRecord] = []
    public private(set) var nextCursor: String?
    public private(set) var pages = 0
    public init() {}
    public var canLoadMore: Bool { pages > 0 && nextCursor != nil }

    /// Reads the first `pages` pages, following the cursor, and replaces the window.
    static func load(_ repository: any ConversationsRepository, account: String, pages: Int, locale: Locale, now: Date) async -> RepositoryResult<ConversationsWindow> {
        var window = ConversationsWindow(), cursor: String?
        var collected: [ConversationRecord] = []
        repeat {
            switch await repository.page(account: account, cursor: cursor, limit: pageSize) {
            case .failure(let failure): return .failure(failure)
            case .success(let page):
                collected += page.rows; cursor = page.nextCursor; window.pages += 1
            }
            if Task.isCancelled { return .failure(.failed) }
        } while cursor != nil && window.pages < max(1, pages)
        window.nextCursor = cursor
        window.rows = project(collected, locale: locale, now: now)
        return .success(window)
    }
    /// Appends the page after the current cursor.
    func appending(_ repository: any ConversationsRepository, account: String, locale: Locale, now: Date) async -> RepositoryResult<ConversationsWindow> {
        guard let cursor = nextCursor else { return .success(self) }
        switch await repository.page(account: account, cursor: cursor, limit: Self.pageSize) {
        case .failure(let failure): return .failure(failure)
        case .success(let page):
            var next = self
            next.pages += 1; next.nextCursor = page.nextCursor
            next.rows = Self.project(rows + page.rows, locale: locale, now: now)
            return .success(next)
        }
    }
    /// Removes duplicate ids (first wins), sorts by last activity (newest first, unknown last, then by id)
    /// and fills the time label. Runs off the main actor; the format styles are built once per call.
    static func project(_ rows: [ConversationRecord], locale: Locale, now: Date) -> [ConversationRecord] {
        var seen = Set<String>(); seen.reserveCapacity(rows.count)
        let unique = rows.filter { seen.insert($0.id).inserted }
        let sorted = unique.sorted { lhs, rhs in
            switch (lhs.lastActivity, rhs.lastActivity) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.id < rhs.id
            }
        }
        let labels = ConversationTimeLabels(locale: locale, now: now)
        return sorted.map { row in
            ConversationRecord(id: row.id, title: row.title, preview: row.preview, lastActivity: row.lastActivity, unreadCount: row.unreadCount,
                               timeLabel: row.lastActivity.map(labels.label) ?? row.timeLabel, kind: row.kind, avatarIcon: row.avatarIcon,
                               muted: row.muted, pinned: row.pinned, readReceipt: row.readReceipt, sender: row.sender)
        }
    }
}

/// Time column of a conversation row: the time today, "yesterday", the weekday within a week, else the date.
struct ConversationTimeLabels: Sendable {
    private let calendar: Calendar
    private let now: Date
    private let time: Date.FormatStyle
    private let weekday: Date.FormatStyle
    private let date: Date.FormatStyle
    private let yesterday: String
    init(locale: Locale, now: Date) {
        var calendar = Calendar(identifier: locale.calendar.identifier); calendar.locale = locale
        self.calendar = calendar; self.now = now
        time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        weekday = Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated)
        date = Date.FormatStyle(locale: locale, calendar: calendar).month(.defaultDigits).day(.defaultDigits)
        yesterday = FeatureConversationsStrings.text("conversations.time.yesterday", locale: locale)
    }
    /// `seconds` is the SDK's Unix time in seconds; a value that only fits milliseconds is read as milliseconds.
    func label(_ seconds: Int64) -> String {
        let value = seconds > 100_000_000_000 ? Double(seconds) / 1000 : Double(seconds)
        let moment = Date(timeIntervalSince1970: value)
        if calendar.isDate(moment, inSameDayAs: now) { return moment.formatted(time) }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(moment, inSameDayAs: previous) { return yesterday }
        if let week = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), moment >= week, moment < now { return moment.formatted(weekday) }
        return moment.formatted(date)
    }
}
