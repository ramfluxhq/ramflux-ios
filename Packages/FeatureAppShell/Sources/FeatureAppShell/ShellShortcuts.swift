// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// Shortcut order for the More hub and the edit-navigation page.
/// Core ids stay visible. Contacts and tasks can move or hide.
public enum ShellShortcuts {
    public static let defaultOrder = "messages-groups-agents-contacts-tasks"

    public static func ids(_ raw: String) -> [String] {
        raw.split(separator: "-").map(String.init).filter { !$0.isEmpty }
    }

    public static func isCore(_ id: String) -> Bool {
        id == "messages" || id == "groups" || id == "agents"
    }

    public static func moreIds(order: String, hidden: String) -> [String] {
        let gone = Set(ids(hidden))
        return ids(order).filter { ($0 == "contacts" || $0 == "tasks") && !gone.contains($0) }
    }

    public static func move(_ order: String, hidden: String, index: Int, delta: Int) -> String {
        let ordered = ids(order)
        let gone = Set(ids(hidden))
        var visible = ordered.filter { !gone.contains($0) }
        let target = index + delta
        guard visible.indices.contains(index), visible.indices.contains(target) else { return order }
        let item = visible.remove(at: index)
        visible.insert(item, at: target)
        var cursor = 0
        return ordered.map { id in
            if gone.contains(id) { return id }
            let next = visible[cursor]
            cursor += 1
            return next
        }.joined(separator: "-")
    }

    public static func hide(_ hidden: String, id: String) -> String {
        if isCore(id) { return hidden }
        return Set(ids(hidden)).union([id]).sorted().joined(separator: "-")
    }

    public static func reveal(_ hidden: String) -> String {
        var gone = ids(hidden)
        guard !gone.isEmpty else { return hidden }
        gone.removeFirst()
        return gone.joined(separator: "-")
    }
}
