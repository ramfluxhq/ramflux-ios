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
///
/// The window is bounded: it keeps at most `maxRows` rows. Scrolling past that evicts rows from the
/// top (the most recent, furthest from the viewport) and remembers only that it did (`evictedAbove`)
/// and the sort position of the first kept row. While rows are evicted, later pages contribute only
/// rows that sort below that position, so the window stays one contiguous slice. Reaching the top of
/// an evicted window reloads the first `refreshPages` pages, as a refresh does.
public struct ConversationsWindow: Sendable, Equatable {
    public static let pageSize = NativeConversationsRepository.pageLimit
    /// Pages re-read on a refresh (about 300 rows); scrolling further loads more again.
    public static let refreshPages = 6
    /// Rows kept in memory at most (scale rule 6).
    public static let maxRows = 300
    public private(set) var rows: [ConversationRecord] = []
    public private(set) var nextCursor: String?
    public private(set) var pages = 0
    /// True once rows above the first kept row were dropped to bound the window.
    public private(set) var evictedAbove = false
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
        window.bound()
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
            var incoming = page.rows
            if evictedAbove, let top = rows.first { incoming.removeAll { Self.precedes($0, top) } }
            next.rows = Self.project(rows + incoming, locale: locale, now: now)
            next.bound()
            return .success(next)
        }
    }
    /// Drops rows from the top until at most `maxRows` remain.
    private mutating func bound() {
        guard rows.count > Self.maxRows else { return }
        rows.removeFirst(rows.count - Self.maxRows)
        evictedAbove = true
    }
    /// Display order: newest activity first, unknown activity last, then by id.
    static func precedes(_ lhs: ConversationRecord, _ rhs: ConversationRecord) -> Bool {
        switch (lhs.lastActivity, rhs.lastActivity) {
        case let (l?, r?) where l != r: return l > r
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id < rhs.id
        }
    }
    /// Removes duplicate ids (first wins), sorts by last activity (newest first, unknown last, then by id)
    /// and fills the time label. Runs off the main actor; the format styles are built once per call.
    static func project(_ rows: [ConversationRecord], locale: Locale, now: Date) -> [ConversationRecord] {
        var seen = Set<String>(); seen.reserveCapacity(rows.count)
        let unique = rows.filter { seen.insert($0.id).inserted }
        let sorted = unique.sorted(by: precedes)
        let labels = ConversationTimeLabels(locale: locale, now: now)
        return sorted.map { row in
            ConversationRecord(id: row.id, title: row.title, preview: row.preview, lastActivity: row.lastActivity, unreadCount: row.unreadCount,
                               timeLabel: row.lastActivity.map(labels.label) ?? row.timeLabel, kind: row.kind, avatarIcon: row.avatarIcon,
                               muted: row.muted, pinned: row.pinned, readReceipt: row.readReceipt, sender: row.sender, groupID: row.groupID)
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
