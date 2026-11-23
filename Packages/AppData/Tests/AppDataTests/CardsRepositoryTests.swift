// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import Synchronization
import RamfluxCore
@testable import AppData

/// Fixtures copied byte for byte from the core (`ramflux-protocol/fixtures/protocol/v1/a2ui_surface`).
enum SurfaceFixtures {
    static let snapshot = #"{"catalogId":"urn:ramflux:catalog:rf-card:1.0","closed":false,"components":[{"@checks":[{"condition":{"@call":"required","args":{"value":{"@path":"/note"}}}}],"action":{"event":{"context":{"mode":"save","note":{"@path":"/note"}},"name":"submit","userMessage":"Saved"}},"child":"submit_label","component":"Button","id":"button"},{"children":["label","input","button"],"component":"Column","id":"form"},{"component":"TextField","id":"input","label":"Comment","value":{"@path":"/note"}},{"component":"Text","id":"label","text":{"@path":"/text"}},{"child":"form","component":"Card","id":"root"},{"component":"Text","id":"submit_label","text":"Save"}],"dataModel":{"note":"base","text":"Hello"},"fallbackText":"Save note","final":[],"metadata":{"extensions":{"example":{"label":"fixture"}}},"surfaceId":"surface"}"#
    static let action = #"{"a2ui":{"action":{"context":{"mode":"save","note":"edited"},"name":"submit","sourceComponentId":"button","surfaceId":"surface","timestamp":"2026-11-14T00:00:00Z","userMessage":"Saved"},"version":"1.0"},"argsHash":"IbnCuQii1KUFKLXiDCOouvXWjZ2Q3LAinHIPOUMLklM","conversationId":"conversation","schema":"ramflux.surface.action.v3","sourceInstance":[],"surfaceHash":"m2qAMxneoSO2SJkW-z-Ijn34ewaA1OCyoz2yfYkrJIQ","surfaceVersion":1}"#
    static let hash = "m2qAMxneoSO2SJkW-z-Ijn34ewaA1OCyoz2yfYkrJIQ"
    static func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    static func get(render: Bool = true, closed: Bool = false, outOfSync: Bool = false, hash: String = SurfaceFixtures.hash, version: UInt64 = 1) throws -> JSONValue {
        .object(["surface_ref": .string("ref-1"), "conversation_id": .string("conversation"), "surface_id": .string("surface"), "author_principal_id": .string("agent"), "render_allowed": .bool(render),
                 "version": .unsigned(version), "surface_hash": .string(hash), "closed": .bool(closed), "out_of_sync": .bool(outOfSync), "fallback_text": .string("Save note"),
                 "snapshot": try json(snapshot), "streams": .object(["/text": .string("open")]), "message_id": .string("msg-1")])
    }
}

@Suite struct CardsRepositoryTests {
    @Test func canonicalHashesMatchTheCoreFixtures() throws {
        let snapshot = try SurfaceFixtures.json(SurfaceFixtures.snapshot)
        #expect(CanonicalJSON.text(snapshot) == SurfaceFixtures.snapshot)
        #expect(CanonicalJSON.hash("ramflux.a2ui.surface_hash.v2", snapshot) == SurfaceFixtures.hash)
        let record = try SurfaceRecord.parse(try SurfaceFixtures.get())
        #expect(record.verified); #expect(record.renderable); #expect(record.actionable)
        #expect(record.text(.path("/text")) == "Hello"); #expect(record.streaming(.path("/text")))
        #expect(record.components["root"]?.kind == .card("form")); #expect(record.components["form"]?.kind == .stack(["label", "input", "button"], horizontal: false))
    }

    @Test func theActionFrameBindsTheShownVersionAndHashExactlyAsTheCoreDoes() throws {
        let record = try SurfaceRecord.parse(try SurfaceFixtures.get())
        let frame = try #require(SurfaceActionFrame.build(record, buttonID: "button", drafts: ["/note": .text("edited")], timestamp: Date(timeIntervalSince1970: 1_794_614_400)))
        #expect(CanonicalJSON.text(frame) == SurfaceFixtures.action)
    }

    @Test func renderAndActionGatesFollowTheDaemon() throws {
        #expect(try !SurfaceRecord.parse(try SurfaceFixtures.get(render: false)).renderable)
        #expect(try !SurfaceRecord.parse(try SurfaceFixtures.get(hash: "tampered")).renderable)
        let closed = try SurfaceRecord.parse(try SurfaceFixtures.get(closed: true))
        #expect(closed.renderable); #expect(!closed.actionable)
        #expect(SurfaceActionFrame.build(closed, buttonID: "button", drafts: [:], timestamp: Date()) == nil)
        #expect(try !SurfaceRecord.parse(try SurfaceFixtures.get(outOfSync: true)).actionable)
    }

    @Test func listPagesGetsEachSurfaceAndActionsRecheckTheVersion() async throws {
        let version = Mutex<UInt64>(1)
        let sent = Mutex<[JSONValue]>([])
        let transport = ProxyTransport { request in
            switch request.method {
            case "surface.list":
                #expect(request.body["conversation_id"] == .string("conversation"))
                return .object(["surfaces": .array([.object(["surface_ref": .string("ref-1")]), .object(["surface_id": .string("gone"), "surface_ref": .string("ref-2"), "removed": .bool(true)])]), "next_cursor": .string("c2")])
            case "surface.get": return try SurfaceFixtures.get(version: version.withLock { $0 })
            case "surface.action":
                sent.withLock { $0.append(request.body) }
                return .object(["accepted": .bool(true), "queued": .bool(false), "delivery_state": .string("submitted")])
            default: Issue.record("Unexpected \(request.method)"); return .null
            }
        }
        let repo = NativeCardsRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), now: { Date(timeIntervalSince1970: 1_794_614_400) })
        guard case .success(let page) = await repo.surfaces(account: "a", conversation: "conversation", cursor: nil) else { Issue.record("List must succeed"); return }
        #expect(page.surfaces.map(\.surfaceRef) == ["ref-1"]); #expect(page.nextCursor == "c2")
        let shown = try #require(page.surfaces.first)
        #expect(await repo.act(account: "a", shown: shown, buttonID: "button", drafts: ["/note": .text("edited")], messageID: "bWVzc2FnZQ") == .success(SurfaceActionOutcome(accepted: true, queued: false, reasonCode: nil)))
        let body = try #require(sent.withLock { $0.first })
        #expect(body["message_id"] == .string("bWVzc2FnZQ")); #expect(body["author_principal_id"] == .string("agent"))
        let wire = try #require(body["wire_base64"]?.string.flatMap { ChatMediaEngine.base64URL($0) })
        #expect(String(decoding: wire, as: UTF8.self) == SurfaceFixtures.action)
        version.withLock { $0 = 2 }
        #expect(await repo.act(account: "a", shown: shown, buttonID: "button", drafts: [:], messageID: "bWVzc2FnZQ") == .failure(.typedRefusal("stale_version")))
        #expect(sent.withLock { $0.count } == 1)
    }
}
