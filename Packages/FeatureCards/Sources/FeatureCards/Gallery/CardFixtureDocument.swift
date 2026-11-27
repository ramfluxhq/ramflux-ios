// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import AppData
import Foundation
import RamfluxCore

/// Conversions the conformance checks need: a held `CardTree` back to `ramflux.card.tree.v1` JSON and the comparison
/// form of the README (live session rewritten to 1, integers by value, `request_id` parsed).
public enum CardFixtureDocument {
    /// The held tree as `ramflux.card.tree.v1`: nodes in preorder from the root, the complete host-slot array.
    public static func treeJSON(_ tree: CardTree) -> JSONValue {
        var nodes: [JSONValue] = []
        var stack: [String] = tree.rootKey.map { [$0] } ?? []
        while let key = stack.popLast() {
            guard let node = tree.nodes[key] else { continue }
            nodes.append(nodeJSON(node))
            stack.append(contentsOf: node.children.reversed())
        }
        var document: [String: JSONValue] = [
            "schema": .string("ramflux.card.tree.v1"),
            "session": .unsigned(tree.session),
            "signed_version": .unsigned(tree.signedVersion),
            "signed_hash": .string(tree.signedHash),
            "edit_seq": .unsigned(tree.editSeq),
            "tree_version": .unsigned(tree.treeVersion),
            "root_key": tree.rootKey.map { JSONValue.string($0) } ?? .null,
            "nodes": .array(nodes),
            "host_slots": .array(tree.hostSlots.map(\.fields)),
            "locale": .string(tree.locale),
            "format_locale": .string(tree.formatLocale),
            "direction": .string(tree.direction),
        ]
        // The runtime omits these when they hold their defaults (`generating` false, `lifecycle` open, no replacement).
        if tree.generating { document["generating"] = .bool(true) }
        if tree.lifecycle != .open { document["lifecycle"] = .string(tree.lifecycle.rawValue) }
        if let replacement = tree.replacementRef { document["replacement_ref"] = .string(replacement) }
        return .object(document)
    }

    /// The comparison form of a `ramflux.card.tree.v1` document whose live session is `live` (the committed trees use
    /// 1). It applies the README rule and nothing more lenient:
    /// - every `session` field equal to `live` becomes 1, at any depth (the tree and every `token.session`);
    /// - a `request_id` is the runtime's token as JSON text: it is parsed and compared as JSON with its `session`
    ///   rewritten too, since the runtime and the fixture generator write its keys in different orders;
    /// - integers compare by value: a decoded document holds `.number` while a held tree writes `.unsigned`;
    /// - nodes are ordered by key (their structure is compared through `parent_key` and each `children` list).
    public static func comparable(_ document: JSONValue, live: UInt64) -> JSONValue {
        guard case .object(var fields) = rebased(document, name: "", live: live) else { return rebased(document, name: "", live: live) }
        if case .array(let nodes)? = fields["nodes"] {
            fields["nodes"] = .array(nodes.sorted { ($0["key"]?.string ?? "") < ($1["key"]?.string ?? "") })
        }
        return .object(fields)
    }

    /// The name of the first top-level field where two comparison forms differ, or "none".
    public static func firstDifference(_ left: JSONValue?, _ right: JSONValue?) -> String {
        guard case .object(let a)? = left, case .object(let b)? = right else { return left == right ? "none" : "document" }
        return Set(a.keys).union(b.keys).sorted().first { a[$0] != b[$0] } ?? "none"
    }

    private static let safeInteger: UInt64 = 9_007_199_254_740_991

    private static func rebased(_ value: JSONValue, name: String, live: UInt64) -> JSONValue {
        switch value {
        case .object(let fields):
            var out: [String: JSONValue] = [:]
            for (key, field) in fields { out[key] = rebased(field, name: key, live: live) }
            return .object(out)
        case .array(let items):
            return .array(items.map { rebased($0, name: "", live: live) })
        case .unsigned(let number):
            if name == "session", number == live { return .number(1) }
            return number <= safeInteger ? .number(Double(number)) : value
        case .number(let number):
            if name == "session", number == Double(live) { return .number(1) }
            return value
        case .string(let text) where name == "request_id":
            guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .object = parsed else { return value }
            return rebased(parsed, name: "", live: live)
        default:
            return value
        }
    }

    private static func nodeJSON(_ node: CardNode) -> JSONValue {
        .object([
            "attrs": node.attrs,
            "children": .array(node.children.map { JSONValue.string($0) }),
            "component_id": .string(node.componentID),
            "key": .string(node.key),
            "kind": .string(node.kind),
            "parent_key": node.parentKey.map { JSONValue.string($0) } ?? .null,
            "scope": .string(node.scope),
            "slot": node.slot,
            "source_instance": node.sourceInstance,
        ])
    }
}
#endif
