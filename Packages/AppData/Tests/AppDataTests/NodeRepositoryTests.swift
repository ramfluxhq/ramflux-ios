// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct NodeRepositoryTests {
    private func discovery(key: String = "node-key", fingerprint: String = "observed") -> JSONValue {
        .object(["node": .object(["node_id": .string("node.example"), "discovery_url": .string("http://node.example"), "node_public_key": .string(key)]), "key_fingerprint": .string(fingerprint)])
    }
    @Test func operatorConfirmationUsesExternalKeyAndNeverDispatchesMismatch() async {
        let body = discovery()
        let transport = ProxyTransport { request in request.method == "node.add" ? body : .object([:]) }
        let repository = NativeNodeRepository(client: RamfluxClient(transport: transport))
        let candidate = NodeRecord(id: "node.example", origin: "http://node.example", fingerprint: "observed", publicKey: "node-key")
        guard case .failure(.nodeKeyMismatch) = await repository.save(candidate, expectedPublicKey: "different", operationID: "pin") else { Issue.record("Mismatched operator key must fail before SDK submission"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
        guard case .success = await repository.save(candidate, expectedPublicKey: "node-key", operationID: "pin") else { Issue.record("Matching independent key must reach node.confirm after fresh discovery"); return }
        let requests = transport.calls.withLock { $0 }
        #expect(requests.map(\.method) == ["node.add", "node.confirm"])
        #expect(requests.first?.body["refresh"] == .bool(true))
        #expect(requests.last?.body["expected_public_key"] == .string("node-key"))
        #expect(requests.last?.body["pin_source"] == .string("operator"))
        #expect(requests.last?.operationID?.rawValue == "pin")
    }
    @Test func keyOrFingerprintSwappedBetweenReviewAndPinNeverReachesConfirm() async {
        for body in [discovery(key: "replacement"), discovery(fingerprint: "replacement")] {
            let transport = ProxyTransport { _ in body }
            let repository = NativeNodeRepository(client: RamfluxClient(transport: transport))
            let reviewed = NodeRecord(id: "node.example", origin: "http://node.example", fingerprint: "observed", publicKey: "node-key")
            guard case .failure(.nodeKeyMismatch) = await repository.save(reviewed, expectedPublicKey: "node-key", operationID: "pin") else { Issue.record("Changed signed discovery must refuse pin"); return }
            #expect(transport.calls.withLock { $0.map(\.method) } == ["node.add"])
        }
    }
    @Test func listDoesNotInventConfirmedTrustForIncompleteProfile() async {
        let transport = ProxyTransport { _ in .object(["nodes": .array([.object(["node_id": .string("node.example"), "discovery_url": .string("HTTP://node.example"), "enabled": .bool(true)])])]) }
        let repository = NativeNodeRepository(client: RamfluxClient(transport: transport))
        guard case .success(let rows) = await repository.list() else { Issue.record("Expected profile list"); return }
        #expect(rows.first?.isConfirmed == false); #expect(rows.first?.canCreateAccount == false)
    }
}
