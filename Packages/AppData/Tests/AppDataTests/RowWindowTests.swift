// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
@testable import AppData
private struct Row: Identifiable, Sendable, Equatable { let id: Int }
private final class Counter: Sendable { let value = Mutex(0); func bump() { value.withLock { $0 += 1 } }; var count: Int { value.withLock { $0 } } }
struct RowWindowTests {
    /// An id-ordered source of `total` rows whose cursor is the last id of the page.
    private func reader(_ total: Int, reads: Counter) -> RowPageReader<Row> {
        { cursor, limit in
            reads.bump()
            let start = cursor.flatMap(Int.init).map { $0 + 1 } ?? 0, end = min(start + limit, total)
            return .success(RowPage(rows: (start..<end).map(Row.init), nextCursor: end < total ? String(end - 1) : nil))
        }
    }
    @Test func fiftyThousandRowsScrollBothWaysInsideTheBound() async {
        let reads = Counter(), read = reader(50_000, reads: reads)
        guard case .success(var window) = await RowWindow.first(read) else { Issue.record("first failed"); return }
        let clock = ContinuousClock()
        let down = await clock.measure {
            while window.canLoadAfter, case .success(let next) = await window.after(read) { window = next; #expect(window.count <= window.maxRows) }
        }
        #expect(window.rows.last?.id == 49_999); #expect(window.count == window.maxRows); #expect(window.pagesRead == 1_000)
        let up = await clock.measure {
            while window.canLoadBefore, case .success(let next) = await window.before(read) { window = next; #expect(window.count <= window.maxRows) }
        }
        #expect(window.rows.first?.id == 0); #expect(window.rows.map(\.id) == Array(0..<window.count)); #expect(window.canLoadAfter)
        guard case .success(let again) = await window.after(read) else { Issue.record("after failed"); return }
        #expect(again.rows.last?.id == window.rows.last.map { $0.id + window.pageSize })
        print("ROW_WINDOW_50K down=\(down) up=\(up) reads=\(reads.count)")
    }
    @Test func patchAndRemoveTouchOnlyHeldRows() async {
        let reads = Counter()
        guard case .success(let window) = await RowWindow.first(pageSize: 5, reader(10, reads: reads)) else { return }
        #expect(window.removing(2).rows.map(\.id) == [0, 1, 3, 4]); #expect(window.patching(Row(id: 9)) == window)
    }
    @Test func snapshotPagerReadsOnceFiltersAndRejectsStaleCursors() async {
        let pager = SnapshotPager<Int>(), reads = Counter()
        let read: @Sendable () async -> RepositoryResult<[Int]> = { reads.bump(); return .success(Array(0..<50_000)) }
        guard case .success(let first) = await pager.page(cursor: nil, limit: 50, read: read, include: { $0 % 2 == 0 }) else { Issue.record("first failed"); return }
        #expect(first.rows.first == 0); #expect(first.rows.last == 98)
        guard case .success(let second) = await pager.page(cursor: first.nextCursor, limit: 50, read: read) else { Issue.record("second failed"); return }
        #expect(second.rows.first == 100); #expect(reads.count == 1)
        _ = await pager.page(cursor: nil, limit: 50, read: read)
        #expect(await pager.page(cursor: second.nextCursor, limit: 50, read: read) == .failure(.resyncRequired))
    }
}
