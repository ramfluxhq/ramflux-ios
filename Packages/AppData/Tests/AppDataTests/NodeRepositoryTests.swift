// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct NodeRepositoryTests {
    @Test func operatorConfirmationUsesExternalKeyAndNeverDispatchesMismatch() async {
        let transport = ProxyTransport { _ in .object([:]) }
        let repository = NativeNodeRepository(client: RamfluxClient(transport: transport))
        let candidate = NodeRecord(id: "node.example", origin: "http://node.example", fingerprint: "observed", publicKey: "node-key")
        guard case .failure(.nodeKeyMismatch) = await repository.save(candidate, expectedPublicKey: "different", operationID: "pin") else { Issue.record("Mismatched operator key must fail before SDK submission"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
        guard case .success = await repository.save(candidate, expectedPublicKey: "node-key", operationID: "pin") else { Issue.record("Matching external operator key must reach node.confirm"); return }
        let requests = transport.calls.withLock { $0 }
        #expect(requests.count == 1)
        #expect(requests.first?.method == "node.confirm")
        #expect(requests.first?.body["expected_public_key"] == .string("node-key"))
        #expect(requests.first?.body["pin_source"] == .string("operator"))
        #expect(requests.first?.operationID?.rawValue == "pin")
    }
}
