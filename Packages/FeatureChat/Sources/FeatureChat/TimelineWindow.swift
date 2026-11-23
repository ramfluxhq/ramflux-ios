// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import AppData

/// The bounded window of read-model rows the chat keeps in memory, newest first.
///
/// It is the chat's paged source: the newest page starts it, older pages are appended through the
/// read model's `next_before` cursor, and change batches patch rows by id. It never holds more
/// than `capacity` rows: loading older history past the cap drops the newest rows and detaches
/// the window from the live end, which the user returns to by reloading the newest page.
/// All operations are value-type work, run off the main actor by the view model.
struct TimelineWindow: Equatable, Sendable {
    static let defaultCapacity = 600
    let capacity: Int
    private(set) var records: [MessageRecord] = []
    /// Cursor of the next older page; nil once the beginning of history is in the window.
    private(set) var nextBefore: MessageCursor?
    /// Journal sequence the window is current through.
    private(set) var journal: UInt64?
    /// True when newer rows were dropped; live changes then only patch rows already shown.
    private(set) var detached = false
    private(set) var loaded = false
    private(set) var needsReload = false

    init(capacity: Int = TimelineWindow.defaultCapacity) { self.capacity = max(1, capacity) }

    var hasOlder: Bool { nextBefore != nil }

    mutating func reset(_ page: MessageWindowPage) {
        records = Array(page.records.prefix(capacity)); nextBefore = page.nextBefore; journal = page.snapshotSequence; detached = false; loaded = true; needsReload = false
        if page.records.count > capacity { nextBefore = nil }
    }

    mutating func appendOlder(_ page: MessageWindowPage) {
        let known = Set(records.map { MessageID.normalized($0.id) })
        records.append(contentsOf: page.records.filter { !known.contains(MessageID.normalized($0.id)) })
        nextBefore = page.nextBefore
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
            detached = true
        }
        records = Self.resolve(records)
    }

    /// Applies one change batch. Rows already in the window are replaced in place (a row whose
    /// order changed is moved); unknown rows are inserted at their order when they fall inside
    /// the window, and ignored when they are older than the window or the window is detached.
    mutating func apply(_ batch: MessageChangeBatch) {
        var index: [String: Int] = [:]
        for (position, record) in records.enumerated() { index[MessageID.normalized(record.id)] = position }
        var removals = Set<String>()
        var insertions: [MessageRecord] = []
        for change in batch.changes {
            switch change {
            case .hidden(let id):
                if index[MessageID.normalized(id)] != nil { removals.insert(MessageID.normalized(id)) }
            case .row(let record):
                let key = MessageID.normalized(record.id)
                if let position = index[key] {
                    if records[position].order == record.order || record.order == nil { records[position] = record }
                    else { removals.insert(key); insertions.append(record) }
                } else if !detached, belongsInWindow(record) {
                    insertions.removeAll { MessageID.normalized($0.id) == key }
                    insertions.append(record)
                }
            }
        }
        if !removals.isEmpty { records.removeAll { removals.contains(MessageID.normalized($0.id)) } }
        for record in insertions { insert(record) }
        // Live growth past the cap cannot keep a valid older cursor for the trimmed rows, so the
        // window asks to be rebuilt from the newest page instead of silently skipping history.
        if records.count > capacity { records.removeLast(records.count - capacity); needsReload = true }
        journal = batch.nextAfter
        records = Self.resolve(records)
    }

    private func belongsInWindow(_ record: MessageRecord) -> Bool {
        guard nextBefore != nil, let oldest = records.last?.order, let order = record.order else { return true }
        return order >= oldest
    }

    /// Binary insertion by display order (newest first). Rows without an order go to the top,
    /// the way the read model lists a just-written row.
    private mutating func insert(_ record: MessageRecord) {
        guard let order = record.order else { records.insert(record, at: 0); return }
        var low = 0, high = records.count
        while low < high {
            let middle = (low + high) / 2
            if let other = records[middle].order, other > order { low = middle + 1 } else { high = middle }
        }
        records.insert(record, at: low)
    }

    private static func resolve(_ records: [MessageRecord]) -> [MessageRecord] {
        var previews: [String: String] = [:]
        for record in records { if case .text(let text) = record.kind { previews[MessageID.normalized(record.id)] = text } }
        return records.map { record in
            guard let reply = record.replyTo, let preview = previews[reply], preview != record.replyPreview else { return record }
            return record.withReplyPreview(preview)
        }
    }
}

enum MessageID {
    /// Read-model ids are base64url; quotes may carry the standard alphabet with padding.
    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
