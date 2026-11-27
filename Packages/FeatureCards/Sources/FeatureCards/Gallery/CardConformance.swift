// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import AppData
import Foundation
import RamfluxCore
import SwiftUI

/// One line of the conformance report: `{id, kind, variant, check, pass, detail}`.
public struct CardConformanceRecord: Equatable, Sendable {
    public let id: String
    public let kind: String
    public let variant: String?
    public let check: String
    public let pass: Bool
    public let detail: String

    public var json: JSONValue {
        .object([
            "id": .string(id), "kind": .string(kind), "variant": variant.map { JSONValue.string($0) } ?? .null,
            "check": .string(check), "pass": .bool(pass), "detail": .string(detail),
        ])
    }
}

/// One row of `host-fixtures/index.json`. `id` is the fixture path without its `.input.json` suffix (`button/primary`).
public struct CardFixtureRow: Equatable, Sendable {
    public let id: String
    public let kind: String
    public let variant: String?
    public let outcome: String
    public let fixture: String
    public let expected: String
}

/// The renderer's answers to check B and the gallery view. The production renderer draws each fixture tree; `undrawn`
/// reports the nodes it cannot draw (placeholders) and the host-slot kinds it has no draw path for.
public protocol CardGalleryDrawing: Sendable {
    /// Keys of the nodes this renderer cannot draw (placeholders) and the host-slot kinds it has no draw path for.
    func undrawn(_ tree: CardTree) -> [String]
    /// The gallery detail for one tree; events the drawing sends go to `onEvent` (the standalone runtime, not a chat).
    @MainActor func view(for tree: CardTree, onEvent: @escaping (String, CardHostEvent) -> Void) -> AnyView
}

/// Checks A-C of the common brief, run on the standalone runtime for every row of `host-fixtures/index.json`.
public struct CardConformance: Sendable {
    public let runtime: CardFixtureRuntime
    public let root: URL
    public let drawing: CardGalleryDrawing

    public init(runtime: CardFixtureRuntime, root: URL, drawing: CardGalleryDrawing = CardRendererDrawing()) {
        self.runtime = runtime; self.root = root; self.drawing = drawing
    }

    /// The kinds whose check C drives an event; Approval has no standalone event (its answers go through a host slot).
    static let interactiveKinds: Set<String> = [
        "TextField", "CheckBox", "ChoicePicker", "Slider", "DateTimeInput", "Button", "Tabs", "Modal", "Approval",
    ]

    public static func rows(root: URL) throws -> [CardFixtureRow] {
        let data = try read(root.appendingPathComponent("host-fixtures").appendingPathComponent("index.json"))
        guard case .array(let cases)? = try JSONDecoder().decode(JSONValue.self, from: data)["cases"] else {
            throw CardFixtureError.fixtureInvalid("index.json has no cases")
        }
        return try cases.map { row in
            guard let kind = row["kind"]?.string, let outcome = row["outcome"]?.string,
                  let fixture = row["fixture"]?.string, let expected = row["expected"]?.string else {
                throw CardFixtureError.fixtureInvalid("index row incomplete")
            }
            let id = fixture.replacingOccurrences(of: ".input.json", with: "")
            return CardFixtureRow(id: id, kind: kind, variant: row["variant"]?.string, outcome: outcome, fixture: fixture, expected: expected)
        }
    }

    /// Runs A-C for every row and returns the records in index order. Every opened handle is disposed.
    public func run() async throws -> [CardConformanceRecord] {
        var records: [CardConformanceRecord] = []
        for row in try Self.rows(root: root) {
            records += await check(row)
        }
        return records
    }

    private func check(_ row: CardFixtureRow) async -> [CardConformanceRecord] {
        let input: Data
        do {
            input = try Self.read(root.appendingPathComponent("host-fixtures").appendingPathComponent(row.fixture))
        } catch {
            return [record(row, "A", false, "input unreadable: \(error)")]
        }
        let opened: CardFixtureCall
        do {
            opened = try await runtime.open(spec: input, locale: "en", dark: false)
        } catch {
            return [record(row, "A", false, "open failed: \(error)")]
        }
        if row.outcome == "refused" {
            let pass = !opened.ok && opened.payload == nil
            if opened.ok { _ = await runtime.dispose(opened.session) }
            return [record(row, "A", pass, "refused by the runtime: status \(opened.status)")]
        }
        guard opened.ok, let batch = opened.payload, let held = try? CardTree().applying(CardMutationBatch.decode(batch)) else {
            if opened.ok { _ = await runtime.dispose(opened.session) }
            return [record(row, "A", false, "open did not return an applicable batch (status \(opened.status))")]
        }
        let records = await evaluate(row, session: opened.session, held: held)
        _ = await runtime.dispose(opened.session)
        return records
    }

    private func evaluate(_ row: CardFixtureRow, session: UInt64, held: CardTree) async -> [CardConformanceRecord] {
        let expectedTree = Self.expectedTree(root: root, row: row)
        let heldDocument = CardFixtureDocument.sessionRewritten(CardFixtureDocument.treeJSON(held))
        let fresh = await runtime.tree(session)
        let freshDocument = fresh.payload.map(CardFixtureDocument.sessionRewritten)
        let heldMatches = heldDocument == expectedTree
        let freshMatches = freshDocument == expectedTree
        var records = [record(row, "A", heldMatches && freshMatches,
                              "held tree \(heldMatches ? "equal" : "differs") and fresh read \(freshMatches ? "equal" : "differs") to the expected tree")]
        let undrawn = drawing.undrawn(held)
        let drawn = !held.nodes.isEmpty && undrawn.isEmpty
        records.append(record(row, "B", drawn, drawn ? "no placeholder, every host slot drawn" : "undrawn: \(undrawn.joined(separator: ", "))"))
        if Self.interactiveKinds.contains(row.kind) {
            records.append(await checkC(row, session: session, held: held, fresh: freshDocument))
        }
        return records
    }

    private func checkC(_ row: CardFixtureRow, session: UInt64, held: CardTree, fresh: JSONValue?) async -> CardConformanceRecord {
        guard let key = Self.preorder(held).first(where: { held.nodes[$0]?.kind == row.kind }), let node = held.nodes[key] else {
            return record(row, "C", false, "no node of kind \(row.kind) to drive")
        }
        guard let event = Self.event(for: node, kind: row.kind) else {
            let equal = fresh == CardFixtureDocument.sessionRewritten(CardFixtureDocument.treeJSON(held))
            return record(row, "C", equal, "no standalone event (host slot answers only); runtime tree equal: \(equal)")
        }
        guard let token = held.token(for: key) else { return record(row, "C", false, "node is not mounted") }
        let tokenJSON: JSONValue = .object([
            "session": .unsigned(token.session), "signedVersion": .unsigned(token.signedVersion),
            "editSeq": .unsigned(token.editSeq), "treeVersion": .unsigned(token.treeVersion), "key": .string(token.key),
        ])
        let reply = await runtime.event(session, input: .object(["token": tokenJSON, "event": event]))
        let eventText = Self.compact(event)
        guard reply.ok, let answer = reply.payload else {
            return record(row, "C", false, "event \(eventText) status \(reply.status)")
        }
        let result = answer["result"]?.string ?? "none"
        var next = held
        if let batchJSON = answer["batch"] {
            do {
                next = try held.applying(CardMutationBatch.decode(batchJSON))
            } catch {
                return record(row, "C", false, "event \(eventText) result \(result): batch does not apply to the held tree")
            }
        }
        let equal = fresh == CardFixtureDocument.sessionRewritten(CardFixtureDocument.treeJSON(next))
        return record(row, "C", equal, "event \(eventText); result \(result); runtime tree equal: \(equal)")
    }

    /// The event the conformance table sends for an interactive node (the same table on every client).
    static func event(for node: CardNode, kind: String) -> JSONValue? {
        switch kind {
        case "TextField":
            return .object(["kind": .string("input"), "value": .string("conformance")])
        case "CheckBox":
            let current: Bool = { if case .bool(let value)? = node.attrs["value"] { return value }; return false }()
            return .object(["kind": .string("input"), "value": .bool(!current)])
        case "ChoicePicker":
            var first: [JSONValue] = []
            if case .array(let options)? = node.attrs["options"], let value = options.first?["value"] { first = [value] }
            return .object(["kind": .string("input"), "value": .array(first)])
        case "Slider":
            return .object(["kind": .string("input"), "value": .unsigned(UInt64(max(0, sliderMidpoint(node))))])
        case "DateTimeInput":
            let dateOnly: Bool = { if case .bool(false)? = node.attrs["enableDate"] { return true }; return false }()
            return .object(["kind": .string("input"), "value": .string(dateOnly ? "09:30" : "2026-11-23")])
        case "Button":
            return .object(["kind": .string("activate")])
        case "Tabs":
            return .object(["kind": .string("select_tab"), "index": .unsigned(1)])
        case "Modal":
            return .object(["kind": .string("modal_open")])
        default:
            return nil
        }
    }

    /// The midpoint of the slider bounds, as a whole number inside them (the core's `validate_input` takes an integer).
    static func sliderMidpoint(_ node: CardNode) -> Int {
        let minimum: Double = { if case .number(let value)? = node.attrs["min"] { return value }; return 0 }()
        let maximum: Double = { if case .number(let value)? = node.attrs["max"] { return value }; return 100 }()
        let mid = ((minimum + maximum) / 2).rounded(.down)
        return Int(min(max(mid, minimum.rounded(.up)), maximum.rounded(.down)))
    }

    static func expectedTree(root: URL, row: CardFixtureRow) -> JSONValue? {
        guard let data = try? read(root.appendingPathComponent("host-fixtures").appendingPathComponent(row.expected)),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return CardFixtureDocument.sessionRewritten(json)
    }

    /// Node keys in document order (preorder from the root).
    static func preorder(_ tree: CardTree) -> [String] {
        var keys: [String] = []
        var stack: [String] = tree.rootKey.map { [$0] } ?? []
        while let key = stack.popLast() {
            guard let node = tree.nodes[key] else { continue }
            keys.append(key)
            stack.append(contentsOf: node.children.reversed())
        }
        return keys
    }

    private func record(_ row: CardFixtureRow, _ check: String, _ pass: Bool, _ detail: String) -> CardConformanceRecord {
        CardConformanceRecord(id: row.id, kind: row.kind, variant: row.variant, check: check, pass: pass, detail: detail)
    }

    private static func compact(_ json: JSONValue) -> String {
        (try? String(data: JSONEncoder.sortedCompact.encode(json), encoding: .utf8)) ?? ""
    }

    private static func read(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CardFixtureError.fixtureMissing(url.lastPathComponent) }
        return try Data(contentsOf: url)
    }
}

extension JSONEncoder {
    static let sortedCompact: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    static let sortedPretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }()
}
#endif
