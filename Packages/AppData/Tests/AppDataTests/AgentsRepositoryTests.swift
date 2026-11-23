// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
struct AgentsRepositoryTests {
    private let wire: JSONValue = .object(["agentAnchor": .string("anchor"), "persona": .object(["name": .string("Nova"), "avatar": .string("orbit"), "responsibility": .string("Weekly")]),
        "lifecycle": .string("active"), "role": .string("assistant"), "access": .object(["dm": .string("contacts"), "groupInviters": .string("owner"), "allowedHumans": .array([.string("h1")])])])
    @Test func listGetEditDeleteAndPendingMapProtocolJSON() async {
        let wire = wire
        let transport = ProxyTransport { request in
            switch request.method {
            case "agent.list", "agent.watch": return .object(["page": .object(["records": .array([wire]), "next": .string("c2"), "journalCursor": .string("j9")])])
            case "agent.operation.get": return .object(["custody": .object(["requestId": .string("r1"), "state": .string("pending"), "expiresAt": .string("1800000000")])])
            default: return .object(["record": wire])
            }
        }
        let repo = NativeAgentsRepository(client: RamfluxClient(transport: transport), updates: NativeUpdateSource(client: RamfluxClient(transport: transport)))
        guard case .success(let page) = await repo.page(account: "a", cursor: "c1", limit: 50) else { Issue.record("page"); return }
        #expect(page.page.rows.first?.persona.name == "Nova"); #expect(page.page.nextCursor == "c2"); #expect(page.journalCursor == "j9")
        #expect(page.page.rows.first?.access.allowedHumans == ["h1"])
        guard case .success(let pending) = await repo.pendingCreation(account: "a") else { Issue.record("pending"); return }
        #expect(pending?.id == "r1"); #expect(pending?.expiresAt == 1_800_000_000)
        guard case .success = await repo.editPersona(account: "a", agent: "anchor", persona: AgentPersona(name: "Nova", avatar: "orbit", responsibility: "")) else { Issue.record("edit"); return }
        guard case .success = await repo.delete(account: "a", agent: "anchor") else { Issue.record("delete"); return }
        let calls = transport.calls.withLock { $0 }
        #expect(calls.map(\.method) == ["agent.list", "agent.operation.get", "agent.persona.edit", "agent.delete"])
        #expect(calls[0].body == .object(["limit": .number(50), "cursor": .string("c1")]))
        #expect(calls[1].body == .object(["operation_id": .string("")]))
        #expect(calls[2].body["confirmed"] == .bool(true)); #expect(calls[3].body == .object(["agent_anchor": .string("anchor"), "confirmed": .bool(true)]))
        #expect(calls.allSatisfy { $0.operationID == nil })
        guard case .failure(.invalidInput) = await repo.editPersona(account: "a", agent: "anchor", persona: AgentPersona(name: " ", avatar: "", responsibility: "")) else { Issue.record("blank name accepted"); return }
    }
}
