// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// One page of rows and the cursor of the page after it (`nil` at the end).
public struct RowPage<Row: Sendable>: Sendable {
    public let rows: [Row]
    public let nextCursor: String?
    public init(rows: [Row], nextCursor: String?) { self.rows = rows; self.nextCursor = nextCursor }
}
extension RowPage: Equatable where Row: Equatable {}

/// Reads a list one page at a time. Every list screen reads through this interface (scale rule 3),
/// whether the SDK pages the list or `SnapshotPager` wraps an unpaged call.
public typealias RowPageReader<Row: Sendable> = @Sendable (_ cursor: String?, _ limit: Int) async -> RepositoryResult<RowPage<Row>>

/// A bounded, bidirectional window over a paged list (scale rule 6).
///
/// The window holds a contiguous run of pages and at most about `maxRows` rows. Appending past the
/// bound evicts the first page, prepending evicts the last; only the start cursor of every page read
/// so far is kept (an id-only index), so an evicted page can be read again when the user scrolls back.
/// Rows are keyed by their stable SDK id; a duplicate id on a later page is dropped.
public struct RowWindow<Row: Identifiable & Sendable & Equatable>: Sendable, Equatable where Row.ID: Sendable {
    public static var defaultPageSize: Int { 50 }
    public static var defaultMaxRows: Int { 300 }
    public let pageSize: Int
    public let maxRows: Int
    private var pages: [[Row]] = []
    /// Start cursor of every page read so far; `starts[0]` is `nil` (the first page).
    private var starts: [String?] = []
    /// Index (into `starts`) of the first page held.
    private var first = 0
    private var tail: String?
    private var reachedEnd = false
    public init(pageSize: Int = Self.defaultPageSize, maxRows: Int = Self.defaultMaxRows) {
        self.pageSize = max(1, pageSize); self.maxRows = max(self.pageSize * 2, maxRows)
    }
    /// A window over rows already in memory (a list the SDK returns whole): one page, and whether more
    /// rows exist beyond it. `after` and `before` leave it unchanged; the owner rebuilds it to grow it.
    public init(rows: [Row], hasMore: Bool, maxRows: Int = Self.defaultMaxRows) {
        self.init(pageSize: Self.defaultPageSize, maxRows: maxRows)
        starts = [nil]; pages = [rows]; reachedEnd = !hasMore
    }
    public var rows: [Row] { pages.flatMap { $0 } }
    public var isEmpty: Bool { pages.allSatisfy(\.isEmpty) }
    public var count: Int { pages.reduce(0) { $0 + $1.count } }
    public var loaded: Bool { !starts.isEmpty }
    public var canLoadAfter: Bool { loaded && !reachedEnd }
    public var canLoadBefore: Bool { first > 0 }
    /// Pages read so far, including evicted ones.
    public var pagesRead: Int { starts.count }

    /// Reads the first page and replaces the window.
    public static func first(pageSize: Int = defaultPageSize, maxRows: Int = defaultMaxRows, _ read: RowPageReader<Row>) async -> RepositoryResult<RowWindow> {
        var window = RowWindow(pageSize: pageSize, maxRows: maxRows)
        switch await read(nil, window.pageSize) {
        case .failure(let failure): return .failure(failure)
        case .success(let page):
            window.starts = [nil]; window.pages = [window.unique(page.rows)]
            window.tail = page.nextCursor; window.reachedEnd = page.nextCursor == nil
            return .success(window)
        }
    }
    /// Reads the page after the last held page; evicts from the front when over the bound.
    public func after(_ read: RowPageReader<Row>) async -> RepositoryResult<RowWindow> {
        guard canLoadAfter, let cursor = tail else { return .success(self) }
        switch await read(cursor, pageSize) {
        case .failure(let failure): return .failure(failure)
        case .success(let page):
            var next = self
            let index = first + pages.count
            if index == next.starts.count { next.starts.append(cursor) } else { next.starts[index] = cursor }
            next.pages.append(next.unique(page.rows))
            next.tail = page.nextCursor; next.reachedEnd = page.nextCursor == nil
            while next.count > maxRows, next.pages.count > 1 { next.pages.removeFirst(); next.first += 1 }
            return .success(next)
        }
    }
    /// Reads the evicted page just before the first held page; evicts from the end when over the bound.
    public func before(_ read: RowPageReader<Row>) async -> RepositoryResult<RowWindow> {
        guard canLoadBefore else { return .success(self) }
        switch await read(starts[first - 1], pageSize) {
        case .failure(let failure): return .failure(failure)
        case .success(let page):
            var next = self
            next.first -= 1
            next.pages.insert(next.unique(page.rows), at: 0)
            while next.count > maxRows, next.pages.count > 1 {
                next.pages.removeLast()
                next.tail = next.starts[next.first + next.pages.count]; next.reachedEnd = false
            }
            return .success(next)
        }
    }
    /// Replaces one row by id (an event patch); a no-op when the row is not held.
    public func patching(_ row: Row) -> RowWindow {
        var next = self
        for index in next.pages.indices { if let at = next.pages[index].firstIndex(where: { $0.id == row.id }) { next.pages[index][at] = row; return next } }
        return next
    }
    /// Removes one row by id from the held pages.
    public func removing(_ id: Row.ID) -> RowWindow {
        var next = self
        for index in next.pages.indices { next.pages[index].removeAll { $0.id == id } }
        return next
    }
    private func unique(_ incoming: [Row]) -> [Row] {
        var seen = Set(rows.map(\.id))
        return incoming.filter { seen.insert($0.id).inserted }
    }
}

/// Pages an unpaged SDK list behind the `RowPageReader` interface.
///
/// A read without a cursor calls the unpaged method once, keeps the matching rows in this actor (off the
/// main actor) and returns the first page; later cursors are offsets into that snapshot. The snapshot
/// lives in the data layer, not in a screen; replacing the SDK call with a paged one only changes the
/// reader. The snapshot's size is bounded by what the SDK returns in one response.
public actor SnapshotPager<Row: Sendable> {
    private var snapshot: [Row] = []
    private var generation: UInt64 = 0
    public init() {}
    public func page(cursor: String?, limit: Int, read: @Sendable () async -> RepositoryResult<[Row]>, include: @Sendable (Row) -> Bool = { _ in true }) async -> RepositoryResult<RowPage<Row>> {
        let limit = max(1, limit)
        var offset = 0
        if let cursor {
            let parts = cursor.split(separator: ":")
            guard parts.count == 2, let epoch = UInt64(parts[0]), let start = Int(parts[1]), start >= 0 else { return .failure(.invalidInput) }
            guard epoch == generation else { return .failure(.resyncRequired) }
            offset = start
        } else {
            switch await read() {
            case .failure(let failure): return .failure(failure)
            case .success(let rows): generation &+= 1; snapshot = rows.filter(include)
            }
        }
        let start = min(offset, snapshot.count), end = min(start + limit, snapshot.count)
        let next = end < snapshot.count ? "\(generation):\(end)" : nil
        return .success(RowPage(rows: Array(snapshot[start..<end]), nextCursor: next))
    }
}
