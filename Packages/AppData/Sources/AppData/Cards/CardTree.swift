// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// A batch or tree the client refuses to apply. The held tree is never changed by a refused batch.
public enum CardTreeError: Error, Equatable, Sendable {
    case malformed
    case versionMismatch
    case limitExceeded
}

/// The fence a host event carries back to the runtime: the token session, the signed version and edit
/// sequence of the tree it was drawn from, and the node key it targets.
public struct CardEventToken: Equatable, Sendable {
    public let session: UInt64
    public let signedVersion: UInt64
    public let editSeq: UInt64
    public let treeVersion: UInt64
    public let key: String
    public init(session: UInt64, signedVersion: UInt64, editSeq: UInt64, treeVersion: UInt64, key: String) {
        self.session = session; self.signedVersion = signedVersion; self.editSeq = editSeq; self.treeVersion = treeVersion; self.key = key
    }
    var json: JSONValue {
        .object(["session": .unsigned(session), "signedVersion": .unsigned(signedVersion), "editSeq": .unsigned(editSeq),
                 "treeVersion": .unsigned(treeVersion), "key": .string(key)])
    }
}

/// One node of `ramflux.card.tree.v1`. `kind` is the runtime's name (`Text`, `Row`, ... `Table`); it is kept as
/// data so a newer runtime kind reaches the renderer as an unknown kind instead of failing the whole tree.
public struct CardNode: Equatable, Sendable {
    public let key: String
    public let componentID: String
    public let parentKey: String?
    public let children: [String]
    public let kind: String
    public let scope: String
    public let attrs: JSONValue
    public let slot: JSONValue
    public let sourceInstance: JSONValue

    init(json: JSONValue) throws {
        guard let key = json["key"]?.string, !key.isEmpty, let componentID = json["component_id"]?.string,
              let kind = json["kind"]?.string, let scope = json["scope"]?.string,
              case .object? = json["attrs"], case .array(let rows)? = json["children"] else { throw CardTreeError.malformed }
        let children = try rows.map { row -> String in guard let key = row.string, !key.isEmpty else { throw CardTreeError.malformed }; return key }
        let parent: String?
        switch json["parent_key"] {
        case .null?, nil: parent = nil
        case .string(let value)?: parent = value
        default: throw CardTreeError.malformed
        }
        self.key = key; self.componentID = componentID; self.parentKey = parent; self.children = children
        self.kind = kind; self.scope = scope; self.attrs = json["attrs"] ?? .object([:])
        self.slot = json["slot"] ?? .null; self.sourceInstance = json["source_instance"] ?? .array([])
    }

    fileprivate func withChildren(_ children: [String]) -> CardNode {
        CardNode(key: key, componentID: componentID, parentKey: parentKey, children: children, kind: kind, scope: scope,
                 attrs: attrs, slot: slot, sourceInstance: sourceInstance)
    }

    private init(key: String, componentID: String, parentKey: String?, children: [String], kind: String, scope: String,
                 attrs: JSONValue, slot: JSONValue, sourceInstance: JSONValue) {
        self.key = key; self.componentID = componentID; self.parentKey = parentKey; self.children = children; self.kind = kind
        self.scope = scope; self.attrs = attrs; self.slot = slot; self.sourceInstance = sourceInstance
    }
}

/// One host slot as the runtime lists it: the complete array replaces the previous one on every commit.
/// `kind` is `approval`, `link_open`, `modal` or `image`; `requestID` fences the slot's reply.
public struct CardHostSlot: Equatable, Sendable {
    public let id: String
    public let key: String
    public let kind: String
    public let requestID: String?
    public let token: CardEventToken
    /// The complete slot object, for the sheet that answers it (approval facts, link URL, ...).
    public let fields: JSONValue

    init(json: JSONValue) throws {
        guard let id = json["id"]?.string, let key = json["key"]?.string, let kind = json["kind"]?.string,
              let token = CardJSON.token(json["token"]) else { throw CardTreeError.malformed }
        self.id = id; self.key = key; self.kind = kind; self.token = token; self.fields = json
        requestID = json["request_id"]?.string
    }
}

public enum CardMutation: Equatable, Sendable {
    case remove(key: String)
    case upsert(parent: String?, index: Int, node: CardNode)
}

/// `ramflux.card.mutations.v1`. A batch with `previousVersion` 0 is a full replacement (open, resume); any other
/// batch applies only to the tree at exactly that version and session.
public struct CardMutationBatch: Equatable, Sendable {
    public static let schema = "ramflux.card.mutations.v1"
    /// The mutation count bound of the runtime (`ramflux-card` README: 512 operations per batch).
    static let maximumMutations = 512
    public let session: UInt64
    public let previousVersion: UInt64
    public let version: UInt64
    public let signedVersion: UInt64
    public let signedHash: String
    public let editSeq: UInt64
    public let mutations: [CardMutation]
    public let hostSlots: [CardHostSlot]
    public let locale: String
    public let formatLocale: String
    public let direction: String

    public static func decode(_ json: JSONValue) throws -> CardMutationBatch {
        guard json["schema"] == .string(schema), let session = CardJSON.uint(json["session"]),
              let previous = CardJSON.uint(json["previous_version"]), let version = CardJSON.uint(json["version"]),
              let signed = CardJSON.uint(json["signed_version"]), let signedHash = json["signed_hash"]?.string,
              let edit = CardJSON.uint(json["edit_seq"]), case .array(let rows)? = json["mutations"],
              rows.count <= maximumMutations, case .array(let slots)? = json["host_slots"],
              let locale = json["locale"]?.string, let formatLocale = json["format_locale"]?.string, let direction = json["direction"]?.string
        else { throw CardTreeError.malformed }
        let mutations = try rows.map(CardMutationBatch.mutation)
        return CardMutationBatch(session: session, previousVersion: previous, version: version, signedVersion: signed, signedHash: signedHash,
                                 editSeq: edit, mutations: mutations, hostSlots: try slots.map(CardHostSlot.init(json:)),
                                 locale: locale, formatLocale: formatLocale, direction: direction)
    }

    private static func mutation(_ json: JSONValue) throws -> CardMutation {
        switch json["op"]?.string {
        case "remove"?:
            guard let key = json["key"]?.string, !key.isEmpty else { throw CardTreeError.malformed }
            return .remove(key: key)
        case "upsert"?:
            guard let index = CardJSON.uint(json["index"]), let node = json["node"] else { throw CardTreeError.malformed }
            let parent: String?
            switch json["parent"] {
            case .null?, nil: parent = nil
            case .string(let value)?: parent = value
            default: throw CardTreeError.malformed
            }
            guard let position = Int(exactly: index) else { throw CardTreeError.malformed }
            return .upsert(parent: parent, index: position, node: try CardNode(json: node))
        default: throw CardTreeError.malformed
        }
    }
}

/// The held native tree of one card session: a flat map keyed by node key, with the root and the complete host slot
/// array. It only changes through `applying(_:)`, which stages a batch and commits it whole or refuses it.
public struct CardTree: Equatable, Sendable {
    public static let maximumNodes = 4096
    public private(set) var session: UInt64
    public private(set) var signedVersion: UInt64
    public private(set) var signedHash: String
    public private(set) var editSeq: UInt64
    /// The tree version: the `version` of the last applied batch (0 before the first one).
    public private(set) var treeVersion: UInt64
    public private(set) var rootKey: String?
    public private(set) var nodes: [String: CardNode]
    public private(set) var hostSlots: [CardHostSlot]
    public private(set) var locale: String
    public private(set) var formatLocale: String
    public private(set) var direction: String

    public init() {
        session = 0; signedVersion = 0; signedHash = ""; editSeq = 0; treeVersion = 0; rootKey = nil
        nodes = [:]; hostSlots = []; locale = "en"; formatLocale = "en"; direction = "ltr"
    }

    public var root: CardNode? { rootKey.flatMap { nodes[$0] } }

    /// The children of a node in document order; keys without a node are skipped (never produced by a valid tree).
    public func children(of key: String) -> [CardNode] { (nodes[key]?.children ?? []).compactMap { nodes[$0] } }

    /// The fence for an event on a node of this tree, or nil when the key is not mounted.
    public func token(for key: String) -> CardEventToken? {
        guard nodes[key] != nil, session != 0 else { return nil }
        return CardEventToken(session: session, signedVersion: signedVersion, editSeq: editSeq, treeVersion: treeVersion, key: key)
    }

    /// Stages `batch` against this tree and returns the result, or throws and leaves this tree as it was.
    public func applying(_ batch: CardMutationBatch) throws -> CardTree {
        let reset = batch.previousVersion == 0
        guard reset || (batch.previousVersion == treeVersion && batch.session == session) else { throw CardTreeError.versionMismatch }
        var nodes: [String: CardNode] = reset ? [:] : self.nodes
        var root: String? = reset ? nil : rootKey
        for mutation in batch.mutations {
            switch mutation {
            case .remove(let key):
                // Shallow: only the node leaves. Descendants are removed by their own ops, which precede it.
                guard let node = nodes[key] else { throw CardTreeError.malformed }
                if let parent = node.parentKey, let owner = nodes[parent] {
                    nodes[parent] = owner.withChildren(owner.children.filter { $0 != key })
                }
                nodes[key] = nil
                if root == key { root = nil }
            case .upsert(let parent, let index, let node):
                if let previous = nodes[node.key], let old = previous.parentKey, let owner = nodes[old], old != parent {
                    nodes[old] = owner.withChildren(owner.children.filter { $0 != node.key })
                }
                if let parent {
                    guard node.parentKey == parent, let owner = nodes[parent] else { throw CardTreeError.malformed }
                    var list = owner.children.filter { $0 != node.key }
                    guard index >= 0, index <= list.count else { throw CardTreeError.malformed }
                    list.insert(node.key, at: index)
                    nodes[parent] = owner.withChildren(list)
                } else {
                    guard node.parentKey == nil else { throw CardTreeError.malformed }
                    if let root, root != node.key { throw CardTreeError.malformed }
                    root = node.key
                }
                nodes[node.key] = node
            }
            guard nodes.count <= Self.maximumNodes else { throw CardTreeError.limitExceeded }
        }
        guard let root, nodes[root] != nil else { throw CardTreeError.malformed }
        try Self.validate(nodes, root: root)
        var next = self
        next.session = batch.session; next.signedVersion = batch.signedVersion; next.signedHash = batch.signedHash
        next.editSeq = batch.editSeq; next.treeVersion = batch.version; next.rootKey = root; next.nodes = nodes
        next.hostSlots = batch.hostSlots; next.locale = batch.locale; next.formatLocale = batch.formatLocale; next.direction = batch.direction
        return next
    }

    /// Every node is reachable from the root exactly once, and every parent link resolves to a listing parent.
    private static func validate(_ nodes: [String: CardNode], root: String) throws {
        for node in nodes.values {
            if let parent = node.parentKey, nodes[parent]?.children.contains(node.key) != true { throw CardTreeError.malformed }
            if node.key != root, node.parentKey == nil { throw CardTreeError.malformed }
        }
        var visited = Set<String>()
        var stack = [root]
        while let key = stack.popLast() {
            guard let node = nodes[key], visited.insert(key).inserted else { throw CardTreeError.malformed }
            stack.append(contentsOf: node.children)
        }
        guard visited.count == nodes.count else { throw CardTreeError.malformed }
    }
}

/// Typed readers for the runtime's JSON. Integers are exact non-negative safe integers only.
enum CardJSON {
    static func uint(_ value: JSONValue?) -> UInt64? {
        let limit: UInt64 = 9_007_199_254_740_991
        switch value {
        case .unsigned(let number)?:
            guard number <= limit else { return nil }
            return number
        case .number(let number)?:
            guard number >= 0, number <= Double(limit), number.rounded() == number else { return nil }
            return UInt64(number)
        default:
            return nil
        }
    }
    static func token(_ value: JSONValue?) -> CardEventToken? {
        guard let session = uint(value?["session"]), let signed = uint(value?["signedVersion"]), let edit = uint(value?["editSeq"]),
              let tree = uint(value?["treeVersion"]), let key = value?["key"]?.string, !key.isEmpty else { return nil }
        return CardEventToken(session: session, signedVersion: signed, editSeq: edit, treeVersion: tree, key: key)
    }
}
