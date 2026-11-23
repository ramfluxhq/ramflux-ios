// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
@testable import AppData
@testable import FeatureChat
import FeatureCards

actor CardsFake: CardsRepository {
    var surfaces: [SurfaceRecord]
    var result: RepositoryResult<SurfaceActionOutcome> = .failure(.offline)
    private(set) var acts: [(String, [String: SurfaceInput], String)] = []
    init(_ surfaces: [SurfaceRecord]) { self.surfaces = surfaces }
    func setResult(_ value: RepositoryResult<SurfaceActionOutcome>) { result = value }
    func availability() async -> RepositoryResult<Void> { .success(()) }
    func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<SurfacePage> { .success(SurfacePage(surfaces: surfaces, nextCursor: nil)) }
    func act(account: String, shown: SurfaceRecord, buttonID: String, drafts: [String: SurfaceInput], messageID: String) async -> RepositoryResult<SurfaceActionOutcome> {
        acts.append((buttonID, drafts, messageID)); return result
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct ChatCardsTests {
    /// A one-button card; the hash is computed so the record verifies like a daemon-sent one.
    static func surface(closed: Bool = false, message: String = "m") throws -> SurfaceRecord {
        let snapshot = #"{"catalogId":"urn:ramflux:catalog:rf-card:1.0","closed":CLOSED,"components":[{"child":"go_label","action":{"event":{"context":{"note":{"@path":"/note"}},"name":"submit"}},"component":"Button","id":"go"},{"component":"Text","id":"go_label","text":"Go"},{"children":["field","go"],"component":"Column","id":"root"},{"component":"TextField","id":"field","label":"Note","value":{"@path":"/note"}}],"dataModel":{"note":"base"},"fallbackText":"Pick one","final":[],"surfaceId":"s"}"#
            .replacingOccurrences(of: "CLOSED", with: closed ? "true" : "false")
        // The hash is computed here so the record verifies like a daemon-sent one.
        let probe = try SurfaceRecord.decode(Data(("{\"surface_ref\":\"ref\",\"surface_id\":\"s\",\"conversation_id\":\"c\",\"version\":3,\"snapshot\":" + snapshot + "}").utf8))
        let hash = probe.snapshot.map { CanonicalJSON.hash("ramflux.a2ui.surface_hash.v2", $0) } ?? ""
        let body = "{\"surface_ref\":\"ref\",\"surface_id\":\"s\",\"conversation_id\":\"c\",\"author_principal_id\":\"agent\",\"message_id\":\"" + message + "\",\"version\":3,\"surface_hash\":\"" + hash
            + "\",\"closed\":" + (closed ? "true" : "false") + ",\"out_of_sync\":false,\"render_allowed\":true,\"fallback_text\":\"Pick one\",\"snapshot\":" + snapshot + "}"
        return try SurfaceRecord.decode(Data(body.utf8))
    }

    @Test func surfacesRenderUnderTheirMessageAndActionsCarryDraftsWithAStableMessageID() async throws {
        let cards = CardsFake([try Self.surface()])
        let model = ChatViewModel(repository: ChatFake(history: [record("m", ms: 1_000)]), cards: cards, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared)
        for _ in 0..<200 where model.state.cards["m"] == nil { try await Task.sleep(for: .milliseconds(5)) }
        let card = try #require(model.state.cards["m"])
        #expect(card.surface.actionable); #expect(card.surface.components["go"] != nil)
        model.send(.surfaceInput(surfaceRef: "ref", pointer: "/note", value: .text("edited")))
        model.send(.surfaceButton(surfaceRef: "ref", buttonID: "go"))
        #expect(model.state.cards["m"]?.sending == true)
        for _ in 0..<200 where await cards.acts.count < 1 || model.state.cards["m"]?.sending == true { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state.cards["m"]?.failure == .offline)
        await cards.setResult(.success(SurfaceActionOutcome(accepted: true, queued: false, reasonCode: nil)))
        model.send(.surfaceButton(surfaceRef: "ref", buttonID: "go"))
        for _ in 0..<200 where await cards.acts.count < 2 || model.state.cards["m"]?.sending == true { try await Task.sleep(for: .milliseconds(5)) }
        let acts = await cards.acts
        #expect(acts.map(\.0) == ["go", "go"]); #expect(acts[0].1["/note"] == .text("edited")); #expect(acts[0].2 == acts[1].2)
        model.send(.disappeared); #expect(model.state.cards.isEmpty)
    }

    @Test func closedSurfacesHaveNoActiveControls() async throws {
        let cards = CardsFake([try Self.surface(closed: true)])
        let model = ChatViewModel(repository: ChatFake(history: [record("m", ms: 1_000)]), cards: cards, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared)
        for _ in 0..<200 where model.state.cards["m"] == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state.cards["m"]?.surface.actionable == false)
        model.send(.surfaceInput(surfaceRef: "ref", pointer: "/note", value: .text("x")))
        model.send(.surfaceButton(surfaceRef: "ref", buttonID: "go"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.state.cards["m"]?.drafts.isEmpty == true); #expect(await cards.acts.isEmpty)
        model.send(.disappeared)
    }
}
