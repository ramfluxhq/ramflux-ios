// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import AppData
import Foundation
import RamfluxCore

/// Conversions the conformance checks need: a held `CardTree` back to `ramflux.card.tree.v1` JSON, the README's
/// session rewrite (every `session` field becomes 1 before a comparison), and the mutation batch a tree is opened from.
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
        return .object([
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
        ])
    }

    /// The README rule: compare with every `session` field rewritten to 1 (the tree, token and request id alike).
    public static func sessionRewritten(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let fields):
            var rewritten: [String: JSONValue] = [:]
            for (key, field) in fields {
                rewritten[key] = key == "session" ? .unsigned(1) : sessionRewritten(field)
            }
            return .object(rewritten)
        case .array(let items):
            return .array(items.map(sessionRewritten))
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
