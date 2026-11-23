// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData

@Suite(.timeLimit(.minutes(1))) struct PairingRepositoryTests {
    static let operation = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    static let token: JSONValue = .object([
        "version": .number(2), "schema": .string("ramflux.pairing.InviteToken.v2"), "recipient_token": .string("rt"),
        "invitation": .object(["signature": .string("sig"), "body": .object(["request_id": .string(operation), "expires_at": .number(1_900_000_300), "capabilities": .array([.string("message"), .string("sync")]), "node_key": .string("nk")])]),
    ])
    static func update(_ phase: String, extra: [String: JSONValue] = [:]) -> JSONValue {
        var value: [String: JSONValue] = ["schema": .string("ramflux.pairing.Update.v2"), "version": .number(2), "operation_id": .string(operation), "generation": .number(1),
            "phase": .string(phase), "expires_at": .number(1_900_000_300), "transcript_hash": .null, "emoji_indices": .null, "peer_ref": .null, "peer_name": .null,
            "capabilities": .array([.string("message"), .string("register"), .string("sync")]), "lease_not_before": .number(1_900_000_000), "lease_expires_at": .number(1_902_592_000),
            "proposal_hash": .null, "record_hash": .null, "result": .null, "cleanup": .string("none")]
        for (key, item) in extra { value[key] = item }
        return .object(["schema": .string("ramflux.pairing.LocalResult.v2"), "version": .number(2), "outcome": .object(["tag": .string("update"), "value": .object(value)])])
    }
    static let peer: [String: JSONValue] = ["transcript_hash": .string("TH"), "peer_name": .string("Desk ‮evil"), "peer_ref": .object(["account_anchor": .string("acc"), "device_id": .string("DEV2"), "device_epoch": .number(1)])]

    @Test func beginSendsTheReferenceBodyAndKeepsOnlyTheCanonicalToken() async throws {
        let transport = ProxyTransport { request in
            #expect(request.method == "device.pair.begin")
            return .object(["schema": .string("ramflux.pairing.LocalResult.v2"), "version": .number(2), "outcome": .object(["tag": .string("begin"), "value": .object([
                "schema": .string("ramflux.pairing.BeginResult.v2"), "version": .number(2), "operation_id": .string(Self.operation), "generation": .number(3),
                "expires_at": .number(1_900_000_300), "invite_token": Self.token])])])
        }
        let repository = NativePairingRepository(client: RamfluxClient(transport: transport), now: { Date(timeIntervalSince1970: 1_900_000_000) })
        guard case .success(let invitation) = await repository.begin(account: "a", deviceName: "  Office Mac ", operationID: "op-1") else { Issue.record("begin failed"); return }
        let body = try #require(transport.calls.withLock { $0.last?.body })
        #expect(body["display_name"] == .string("Office Mac"))
        #expect(body["capabilities"] == .array([.string("message"), .string("register"), .string("sync")]))
        #expect(body["lease_not_before"] == .unsigned(1_900_000_000) && body["lease_expires_at"] == .unsigned(1_902_592_000))
        #expect(invitation.operation == PairingOperation(id: Self.operation, generation: 3))
        #expect(invitation.expiresAt == Date(timeIntervalSince1970: 1_900_000_300))
        let canonical = invitation.withToken { String(decoding: $0, as: UTF8.self) }
        #expect(canonical == #"{"invitation":{"body":{"capabilities":["message","sync"],"expires_at":1900000300,"node_key":"nk","request_id":"\#(Self.operation)"},"signature":"sig"},"recipient_token":"rt","schema":"ramflux.pairing.InviteToken.v2","version":2}"#)
        #expect("\(invitation)" == "PairingInvitation")
        invitation.erase()
        #expect(invitation.isErased && invitation.withToken { _ in true } == nil)
    }
    @Test func beginRefusesBadNamesLocallyAndMapsTypedErrors() async {
        let transport = ProxyTransport { _ in .object(["schema": .string("ramflux.pairing.LocalResult.v2"), "version": .number(2), "outcome": .object(["tag": .string("error"), "error": .object(["code": .string("PrimaryRequired")])])]) }
        let repository = NativePairingRepository(client: RamfluxClient(transport: transport))
        for name in ["", "   ", String(repeating: "x", count: 129), "a\u{202E}b", "tab\u{7}"] {
            guard case .failure(.pairing(.deviceName)) = await repository.begin(account: "a", deviceName: name, operationID: "op") else { Issue.record("accepted \(name.debugDescription)"); return }
        }
        #expect(transport.calls.withLock { $0.isEmpty })
        guard case .failure(.pairing(.primaryRequired)) = await repository.begin(account: "a", deviceName: "Mac", operationID: "op") else { Issue.record("typed error lost"); return }
    }
    @Test func beginRefusesATokenBoundToAnotherOperation() async {
        let transport = ProxyTransport { _ in .object(["schema": .string("ramflux.pairing.LocalResult.v2"), "version": .number(2), "outcome": .object(["tag": .string("begin"), "value": .object([
            "operation_id": .string("OTHER"), "generation": .number(1), "expires_at": .number(1), "invite_token": Self.token])])]) }
        guard case .failure(.invalidData) = await NativePairingRepository(client: RamfluxClient(transport: transport)).begin(account: "a", deviceName: "Mac", operationID: "op") else { Issue.record("mismatched token accepted"); return }
    }
    @Test func statusMapsPhasesPeerFactsAndSymbols() async throws {
        let transport = ProxyTransport { _ in Self.update("sas_pending", extra: Self.peer.merging(["emoji_indices": .array((0..<7).map { .number(Double($0 * 9)) })]) { $1 }) }
        let repository = NativePairingRepository(client: RamfluxClient(transport: transport))
        guard case .success(let progress) = await repository.status(account: "a", operation: PairingOperation(id: Self.operation, generation: 1)) else { Issue.record("status failed"); return }
        #expect(progress.phase == .sasPending && progress.canCompare && !progress.canApprove)
        #expect(progress.emoji == [0, 9, 18, 27, 36, 45, 54] && progress.peerDeviceID == "DEV2" && progress.peerName == "Desk ‮evil")
        #expect(progress.leaseExpiresAt == Date(timeIntervalSince1970: 1_902_592_000))
        let request = try #require(transport.calls.withLock { $0.last })
        #expect(request.method == "device.pair.status" && request.body["schema"] == .string("ramflux.pairing.StatusRequest.v2") && request.body["generation"] == .unsigned(1))
    }
    @Test func positiveConfirmationRechecksTheTranscript() async {
        let calls = ProxyTransport { request in
            if request.method == "device.pair.status" { return Self.update("sas_pending", extra: Self.peer.merging(["transcript_hash": .string("CHANGED"), "emoji_indices": .array((0..<7).map { _ in .number(1) })]) { $1 }) }
            return Self.update("mutually_confirmed", extra: Self.peer)
        }
        let repository = NativePairingRepository(client: RamfluxClient(transport: calls))
        let shown = PairingProgress(operation: PairingOperation(id: Self.operation, generation: 1), phase: .sasPending, expiresAt: .distantFuture, transcriptHash: "TH", emoji: Array(repeating: 1, count: 7), peerDeviceID: "DEV2", peerName: "Desk")
        guard case .failure(.pairing(.comparisonChanged)) = await repository.confirm(account: "a", shown: shown, matches: true, operationID: "c1") else { Issue.record("changed transcript confirmed"); return }
        #expect(!calls.calls.withLock { $0.contains { $0.method == "device.pair.confirm" } })
        guard case .success = await repository.confirm(account: "a", shown: shown, matches: false, operationID: "c2") else { Issue.record("mismatch report failed"); return }
        let confirm = calls.calls.withLock { $0.last }
        #expect(confirm?.method == "device.pair.confirm" && confirm?.body["match"] == .bool(false) && confirm?.body["transcript_hash"] == .string("TH"))
    }
    @Test func approvalCarriesTheReviewedHashesOnly() async throws {
        let transport = ProxyTransport { _ in Self.update("prepared", extra: Self.peer.merging(["proposal_hash": .string("PH")]) { $1 }) }
        let repository = NativePairingRepository(client: RamfluxClient(transport: transport))
        let unready = PairingProgress(operation: PairingOperation(id: Self.operation, generation: 1), phase: .mutuallyConfirmed, expiresAt: .distantFuture, transcriptHash: "TH")
        guard case .failure(.invalidInput) = await repository.approve(account: "a", reviewed: unready, approved: true, operationID: "x") else { Issue.record("approved without a proposal"); return }
        let reviewed = PairingProgress(operation: PairingOperation(id: Self.operation, generation: 1), phase: .proposalPending, expiresAt: .distantFuture, transcriptHash: "TH", peerDeviceID: "DEV2", peerName: "Desk", proposalHash: "PH")
        guard case .success(let after) = await repository.approve(account: "a", reviewed: reviewed, approved: true, operationID: "ap") else { Issue.record("approve failed"); return }
        #expect(after.phase == .prepared)
        let request = try #require(transport.calls.withLock { $0.last })
        #expect(request.method == "device.pair.approve" && request.body["proposal_hash"] == .string("PH") && request.body["approved"] == .bool(true) && request.operationID?.rawValue == "ap")
    }
    @Test func terminalResultsAndCancel() async {
        let transport = ProxyTransport { _ in Self.update("expired", extra: ["result": .string("Expired")]) }
        let repository = NativePairingRepository(client: RamfluxClient(transport: transport))
        guard case .success(let progress) = await repository.cancel(account: "a", operation: PairingOperation(id: Self.operation, generation: 1), operationID: "cx") else { Issue.record("cancel failed"); return }
        #expect(progress.phase.isTerminal && progress.result == "Expired")
        #expect(transport.calls.withLock { $0.last?.method } == "device.pair.cancel")
    }
    @Test func canonicalReaderRefusesFractionsAndDuplicateKeys() throws {
        for source in [#"{"a":1.5}"#, #"{"a":1,"a":2}"#, #"{"a":"x"#] {
            var bytes = Array(source.utf8)
            let refused = bytes.withUnsafeMutableBufferPointer { buffer -> Bool in
                let reader = SealedPairingFrame.Reader(bytes: UnsafeBufferPointer(buffer))
                var out: [UInt8] = []
                do { try reader.canonical(try reader.value(at: 0), into: &out); return false } catch { return true }
            }
            #expect(refused, "accepted \(source)")
        }
    }
}
